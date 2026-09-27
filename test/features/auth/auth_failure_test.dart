import 'package:flutter_test/flutter_test.dart';
import 'package:moaen/features/auth/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every response observed from the live project while diagnosing the emulator
/// sign-in failure, as (code, message) pairs.
///
/// The messages are recorded verbatim rather than reconstructed from
/// documentation, because the whole point of the fallback path in [reasonFor] is
/// that it recognises wording GoTrue may change. Asserting against a paraphrase
/// would not exercise the strings that actually arrive.
const List<(String?, String)> _observed = <(String?, String)>[
  // POST /auth/v1/signup with the Email provider switched off.
  ('email_provider_disabled', 'Email signups are disabled'),
  // POST /auth/v1/token?grant_type=password with the same provider off. Note
  // this arrives on sign-in too, with a different status and different prose.
  ('email_provider_disabled', 'Email logins are disabled'),
];

void main() {
  group('AuthRepository.reasonFor', () {
    test('a disabled email provider is its own reason, not a generic one', () {
      // The regression this exists for. Both responses used to fall through to
      // [AuthFailureReason.unrecognised] and render "Something went wrong.
      // Please try again." while the entire app was unusable.
      for (final (String? code, String message) in _observed) {
        expect(
          AuthRepository.reasonFor(
            AuthException(message, statusCode: '400', code: code),
          ),
          AuthFailureReason.providerDisabled,
          reason: 'the two responses are worded differently but mean one thing',
        );
      }
    });

    test('a wrong password is a wrong password', () {
      expect(
        AuthRepository.reasonFor(
          const AuthException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
        ),
        AuthFailureReason.invalidCredentials,
      );
    });

    test('an unconfirmed address asks for confirmation, not a re-try', () {
      expect(
        AuthRepository.reasonFor(
          const AuthException(
            'Email not confirmed',
            statusCode: '400',
            code: 'email_not_confirmed',
          ),
        ),
        AuthFailureReason.emailNotConfirmed,
      );
    });

    test('a registered address is not offered as a new account', () {
      expect(
        AuthRepository.reasonFor(
          const AuthException(
            'User already registered',
            statusCode: '422',
            code: 'user_already_exists',
          ),
        ),
        AuthFailureReason.alreadyRegistered,
      );
    });

    test('a rate limit is not reported as an unknown fault', () {
      // The prose says "too many requests", not "rate limit" — a message-only
      // match on the words in the code misses the most common shape of this
      // error entirely.
      expect(
        AuthRepository.reasonFor(
          const AuthException(
            'Too many requests have been made. Please wait a bit.',
            statusCode: '429',
            code: 'over_request_rate_limit',
          ),
        ),
        AuthFailureReason.rateLimited,
      );
    });

    test('a per-channel throttle advises the same as a general one', () {
      for (final String code in <String>[
        'over_email_send_rate_limit',
        'over_sms_send_rate_limit',
      ]) {
        expect(
          AuthRepository.reasonFor(
            AuthException('For security purposes, please wait', statusCode: '429', code: code),
          ),
          AuthFailureReason.rateLimited,
        );
      }
    });

    // Not redundancy. GoTrue has renamed these strings across releases, and an
    // app pointed at an older server should still recognise the prose it gets
    // rather than degrade to a generic error and tell the user to try again.
    group('falls back to the message when there is no code', () {
      test('invalid login credentials', () {
        expect(
          AuthRepository.reasonFor(const AuthException('Invalid login credentials')),
          AuthFailureReason.invalidCredentials,
        );
      });

      test('email not confirmed', () {
        expect(
          AuthRepository.reasonFor(const AuthException('Email not confirmed')),
          AuthFailureReason.emailNotConfirmed,
        );
      });

      test('already registered', () {
        expect(
          AuthRepository.reasonFor(const AuthException('User already registered')),
          AuthFailureReason.alreadyRegistered,
        );
      });

      test('signups not allowed', () {
        expect(
          AuthRepository.reasonFor(const AuthException('Signups not allowed for otp')),
          AuthFailureReason.signupsDisabled,
        );
      });

      test('a provider that is off, with no code to say so', () {
        expect(
          AuthRepository.reasonFor(const AuthException('Email logins are disabled')),
          AuthFailureReason.providerDisabled,
        );
      });
    });

    // A code the app has never seen is honestly "unrecognised" rather than
    // guessed at, and the detail survives for the log. Anything landing here
    // during a smoke test is a gap worth filling.
    test('an unmodelled code is reported as unrecognised, not guessed', () {
      const AuthException error = AuthException(
        'Something new happened',
        statusCode: '500',
        code: 'some_future_code',
      );

      expect(
        AuthRepository.reasonFor(error),
        AuthFailureReason.unrecognised,
      );
    });

    test('a transport failure with no response at all is unrecognised', () {
      expect(
        AuthRepository.reasonFor(const AuthException('Connection closed')),
        AuthFailureReason.unrecognised,
      );
    });
  });

  group('AuthFailure', () {
    test('keeps the server detail out of the display path', () {
      const AuthFailure failure = AuthFailure(
        AuthFailureReason.providerDisabled,
        detail: 'Email logins are disabled',
      );

      // The detail is the only field that identifies the fault precisely, so it
      // is kept — for the log. `AuthRepository.reasonFor` is what the UI turns
      // into a sentence, and it never reads this.
      expect(failure.reason, AuthFailureReason.providerDisabled);
      expect(failure.detail, 'Email logins are disabled');
      expect(failure.toString(), contains('providerDisabled'));
    });

    test('renders as a reason alone when there is no detail', () {
      const AuthFailure failure = AuthFailure(AuthFailureReason.rateLimited);

      expect(failure.toString(), 'AuthFailure(rateLimited)');
    });
  });
}
