/// Build-time configuration for the Moaen client.
///
/// Values arrive through `--dart-define`, so they are compile-time constants:
///
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxxxxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
/// ```
///
/// The publishable key is public by design. It ships inside every binary and
/// Row Level Security, not this key, is what protects the data. A secret or
/// service-role key must never be compiled into a mobile app: it bypasses RLS
/// entirely.
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static const String appName = 'Moaen';

  /// Build variants that only need the UI to render can skip the backend.
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// Throws [AppConfigurationError] with an actionable message when the app was
  /// built without credentials. Called once during bootstrap so the failure
  /// surfaces immediately rather than as a confusing network error later.
  static void validate() {
    if (!isSupabaseConfigured) {
      throw const AppConfigurationError(
        'Supabase is not configured for this build. Rebuild with '
        '--dart-define=SUPABASE_URL=<url> '
        '--dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>.',
      );
    }

    final Uri? uri = Uri.tryParse(supabaseUrl);
    if (uri == null || !uri.hasScheme || !uri.host.isNotEmpty) {
      throw AppConfigurationError(
        'SUPABASE_URL is not an absolute http(s) URL: $supabaseUrl',
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
