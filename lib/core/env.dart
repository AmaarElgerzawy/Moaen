import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

/// Build-time configuration for the Moaen client.
///
/// Values normally arrive through `--dart-define`:
///
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxxxxxx.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// ```
///
/// A debug build does not need them: it falls back to [_devSupabaseUrl] and
/// [_devSupabaseKey] so that a bare `flutter run` on an emulator works. Pass the
/// defines to point a debug build at a different project; the defines always
/// win.
///
/// The publishable key is public by design. It ships inside every binary and
/// Row Level Security, not this key, is what protects the data. A secret or
/// service-role key must never be compiled into a mobile app: it bypasses RLS
/// entirely.
class Env {
  const Env._();

  // ---------------------------------------------------------------------------
  // Development fallback
  //
  // Deliberately debug-only. A release or profile build must never fall back to
  // the development project, because that would silently ship production users
  // onto a database meant for testing, and it would do so quietly — the app
  // would start, look healthy, and quietly write to the wrong place. In those
  // build modes both fallbacks compile to the empty string and [validate]
  // throws, exactly as it did before these defaults existed.
  //
  // Forking the project? Change these two constants, and expect to supply
  // `--dart-define` for anything other than local debugging.
  // ---------------------------------------------------------------------------

  static const String _devSupabaseUrl =
      'https://ybglobvcqgkfclvkjkri.supabase.co';
  static const String _devSupabaseKey =
      'sb_publishable_qGZ3U2FHarEMD9Mtsg8mHg_eYsNswOp';

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: kDebugMode ? _devSupabaseUrl : '',
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: kDebugMode ? _devSupabaseKey : '',
  );

  static const String appName = 'Moaen';

  /// Build variants that only need the UI to render can skip the backend.
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// True when this build is talking to the development project because no
  /// `--dart-define` was supplied.
  ///
  /// Recorded in the boot log so a log file always states which backend the app
  /// actually reached. That is the difference between a smoke test that proves
  /// the right thing and one that passes against the wrong project.
  static bool get isUsingDevDefaults =>
      kDebugMode &&
      supabaseUrl == _devSupabaseUrl &&
      supabasePublishableKey == _devSupabaseKey;

  /// Throws [AppConfigurationError] with an actionable message when the app was
  /// built without credentials. Called once during bootstrap so the failure
  /// surfaces immediately rather than as a confusing network error later.
  static void validate() =>
      validateCredentials(supabaseUrl, supabasePublishableKey);

  /// The validation itself, over explicit values rather than the build's own.
  ///
  /// Split out from [validate] because the only builds with a problem to
  /// report are the ones *missing* credentials — which, since the development
  /// fallback, are release builds. A test cannot make itself a release build,
  /// so these failure paths would otherwise go untested. Taking the values as
  /// parameters makes every branch reachable from a debug test.
  @visibleForTesting
  static void validateCredentials(String url, String key) {
    if (url.isEmpty || key.isEmpty) {
      throw const AppConfigurationError(
        'Supabase is not configured for this build. A debug build falls back '
        'to the development project automatically, so this can only happen in '
        'a release or profile build — supply '
        '--dart-define=SUPABASE_URL=<url> and '
        '--dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>.',
      );
    }

    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw AppConfigurationError(
        'SUPABASE_URL is not an absolute http(s) URL: $url',
      );
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw AppConfigurationError(
        'SUPABASE_URL must use http or https, found "${uri.scheme}".',
      );
    }
  }
}

/// Raised for a build-time misconfiguration, as opposed to a runtime failure.
class AppConfigurationError implements Exception {
  const AppConfigurationError(this.message);

  final String message;

  @override
  String toString() => 'AppConfigurationError: $message';
}
