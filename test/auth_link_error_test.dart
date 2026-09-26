import 'package:flutter_test/flutter_test.dart';
import 'package:sellora/core/utils/auth_link_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AuthLinkError.fromUri', () {
    test('reads an expired link from the fragment (implicit flow)', () {
      final error = AuthLinkError.fromUri(Uri.parse(
          'https://sellora.app/#error=access_denied&error_code=otp_expired'
          '&error_description=Email+link+is+invalid+or+has+expired'));
      expect(error?.code, 'otp_expired');
      expect(error?.description, 'Email link is invalid or has expired');
      expect(error?.isWrongDevice, isFalse);
    });

    test('reads a PKCE error from the query', () {
      final error = AuthLinkError.fromUri(Uri.parse(
          'https://sellora.app/?error=access_denied&error_code=flow_state_not_found'));
      expect(error?.code, 'flow_state_not_found');
      expect(error?.isWrongDevice, isTrue);
    });

    test('falls back to `error` when there is no error_code', () {
      expect(
          AuthLinkError.fromUri(
                  Uri.parse('https://sellora.app/#error=server_error'))
              ?.code,
          'server_error');
    });

    test('ignores ordinary URLs, including hash routes with a query', () {
      expect(AuthLinkError.fromUri(Uri.parse('https://sellora.app/')), isNull);
      expect(
          AuthLinkError.fromUri(
              Uri.parse('https://sellora.app/#/s/amina?tab=cart')),
          isNull);
      expect(
          AuthLinkError.fromUri(
              Uri.parse('sellora://auth-callback?code=abc123')),
          isNull);
    });
  });

  group('AuthLinkError.fromException', () {
    test('reads the error_code getSessionFromUrl puts in statusCode', () {
      final error = AuthLinkError.fromException(const AuthException(
          'Email link is invalid or has expired',
          statusCode: 'otp_expired',
          code: 'access_denied'));
      expect(error?.code, 'otp_expired');
    });

    test('treats a missing PKCE verifier as a wrong-device link', () {
      final error = AuthLinkError.fromException(const AuthException(
          'Code verifier could not be found in local storage.'));
      expect(error?.isWrongDevice, isTrue);
    });

    test('ignores ordinary API failures', () {
      expect(
          AuthLinkError.fromException(const AuthException(
              'Invalid login credentials',
              statusCode: '400')),
          isNull);
      expect(AuthLinkError.fromException(StateError('offline')), isNull);
    });
  });
}
