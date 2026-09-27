import 'package:supabase_flutter/supabase_flutter.dart';

/// A Supabase client for unit and widget tests.
///
/// Two properties matter, neither of them about the network:
///
///  * **No I/O.** Constructing the client only derives URLs, so it is safe to
///    build one inside a test body.
///  * **No background timer.** [GoTrueClient] starts a ten-second periodic
///    auto-refresh timer in its constructor, and Flutter's test binding fails
///    any test that leaves a timer pending after the widget tree is disposed.
///    That failure surfaces as an unrelated-looking assertion, so the timer is
///    switched off here rather than discovered one test at a time.
SupabaseClient createTestClient() => SupabaseClient(
  'https://test-moaen.supabase.co',
  'test-publishable-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);
