import 'package:flutter/foundation.dart';

/// Sends a report to the backend: `report_client_error(message, stack,
/// context)` (supabase/migrations/20261003000200_admin_platform.sql).
typedef ErrorSink = Future<void> Function(
    String message, String? stack, Map<String, dynamic> context);

/// Ships uncaught errors to the `client_errors` table, where admin reads
/// them under Activity → App errors. It's the in-house stand-in until a
/// crash-reporting service is chosen (SELLORA_IMPLEMENTATION_PLAN.md
/// PHASE 12).
///
/// Errors are often thrown in a loop (an error in build() fires once per
/// frame), so the reporter sends each distinct message at most once per
/// [dedupeWindow] and at most [maxPerSession] reports per run. The server
/// also rate-limits per user. Reporting never throws.
class ErrorReporter {
  ErrorReporter({
    required ErrorSink send,
    this.context = _noContext,
    this.maxPerSession = 20,
    this.dedupeWindow = const Duration(minutes: 5),
    DateTime Function()? clock,
  })  : _send = send,
        _clock = clock ?? DateTime.now;

  final ErrorSink _send;
  final DateTime Function() _clock;

  /// What the app knows at the time of the error: route, platform, release.
  final Map<String, dynamic> Function() context;
  final int maxPerSession;
  final Duration dedupeWindow;

  int _sent = 0;
  final _lastSent = <String, DateTime>{};

  static const maxMessageLength = 2000;
  static const maxStackLength = 8000;

  static Map<String, dynamic> _noContext() => const {};

  /// Reports [error]. Returns whether a report was sent.
  Future<bool> report(Object error, StackTrace? stack,
      {String source = 'app'}) async {
    final message = _truncate(error.toString(), maxMessageLength);
    final key = message.split('\n').first;
    final now = _clock();
    final last = _lastSent[key];
    if (_sent >= maxPerSession ||
        (last != null && now.difference(last) < dedupeWindow)) {
      return false;
    }
    _sent++;
    _lastSent[key] = now;
    try {
      await _send(
        message,
        stack == null ? null : _truncate(stack.toString(), maxStackLength),
        {...context(), 'source': source},
      );
      return true;
    } catch (_) {
      // Reporting is best-effort; the app mustn't fail because of it.
      return false;
    }
  }

  /// Routes Flutter's framework errors and uncaught async errors here.
  /// Framework errors are still printed as usual.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      (previous ?? FlutterError.presentError)(details);
      report(details.exception, details.stack, source: 'flutter');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Uncaught error: $error\n$stack');
      report(error, stack, source: 'platform');
      return true;
    };
  }

  static String _truncate(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}
