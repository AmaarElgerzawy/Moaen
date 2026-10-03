import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_logger.dart';
import 'commission.dart';

/// The platform commission, read from `public.platform_settings`.
///
/// Its own repository rather than a method on `AdminRepository`, because the two
/// halves of the commission have different audiences and only one of them is
/// administrative. Writing it is an admin's job — RLS says so and nothing else
/// needs it. *Reading* it is every buyer's and every inspector's: the create form
/// has to quote the fee it will be charged, and the inspector's offer sheet has to
/// show what the buyer will pay on top of their net. Leaving the read inside the
/// admin repository would make the inspections feature import from the admin feature
/// to price its own form, and that dependency would be wrong in the same direction
/// for every feature added after this one.
///
/// Reads only. The write is [AdminRepository.setCommission] and stays there, because
/// "who may change this" and "who may quote this" are genuinely different questions.
class CommissionRepository {
  CommissionRepository(this._client);

  final SupabaseClient _client;

  static const String _settings = 'platform_settings';

  /// The commission as configured.
  ///
  /// Falls back to [Commission.defaultFixedValue] — migration 0011's own default,
  /// which is also the figure the design was built around — rather than throwing when
  /// the row is missing. The fallback matters twice over: a settings screen that will
  /// not open because a single-row table has no row is a screen an admin cannot fix
  /// from the app, and a create form that refuses to render because it could not price
  /// the request would block a buyer from filing one at all. The database is still the
  /// authority on what gets charged — this number is only ever a *quote*, and the row
  /// a request ends up with is snapshotted from the table by `enforce_bidding`.
  Future<Commission> commission() async {
    try {
      final List<Map<String, dynamic>> rows =
          await _client.from(_settings).select().limit(1);
      if (rows.isEmpty) return const Commission();
      return Commission.fromRow(rows.first);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('commission read failed', error, stackTrace);
      // Not rethrown. The caller's alternative is a form that cannot state a price,
      // and [Commission.defaultFixedValue] is the number the platform was built to
      // charge; a create form showing the design's own figure beats a form that will
      // not open. The row, not this read, decides what is actually charged.
      return const Commission();
    }
  }
}