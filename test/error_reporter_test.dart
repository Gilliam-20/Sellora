import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/core/monitoring/error_reporter.dart';

void main() {
  late List<(String, String?, Map<String, dynamic>)> sent;
  late DateTime now;

  ErrorReporter reporter({int maxPerSession = 20, bool failing = false}) =>
      ErrorReporter(
        send: (message, stack, context) async {
          if (failing) throw Exception('offline');
          sent.add((message, stack, context));
        },
        context: () => {'route': '/s/amina'},
        maxPerSession: maxPerSession,
        clock: () => now,
      );

  setUp(() {
    sent = [];
    now = DateTime(2026, 10, 3, 12);
  });

  test('sends the message, stack and context', () async {
    final ok = await reporter()
        .report(StateError('boom'), StackTrace.current, source: 'flutter');
    expect(ok, isTrue);
    expect(sent.single.$1, 'Bad state: boom');
    expect(sent.single.$2, isNotEmpty);
    expect(sent.single.$3, {'route': '/s/amina', 'source': 'flutter'});
  });

  test('a repeat inside the window is dropped, after it is sent again',
      () async {
    final r = reporter();
    await r.report(Exception('loop\nframe 1'), null);
    await r.report(Exception('loop\nframe 2'), null);
    expect(sent, hasLength(1));
    now = now.add(const Duration(minutes: 6));
    await r.report(Exception('loop\nframe 3'), null);
    expect(sent, hasLength(2));
  });

  test('distinct errors are each sent, up to the session cap', () async {
    final r = reporter(maxPerSession: 3);
    for (var i = 0; i < 5; i++) {
      await r.report(Exception('error $i'), null);
    }
    expect(sent, hasLength(3));
  });

  test('long messages and stacks are truncated', () async {
    await reporter().report('x' * 5000, StackTrace.fromString('y' * 10000));
    expect(sent.single.$1, hasLength(ErrorReporter.maxMessageLength));
    expect(sent.single.$2, hasLength(ErrorReporter.maxStackLength));
  });

  test('a failed send never throws', () async {
    expect(await reporter(failing: true).report(Exception('x'), null), isFalse);
  });
}
