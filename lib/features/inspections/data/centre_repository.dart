import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/inspection_centre.dart';
import 'inspection_repository.dart';

/// Reads of `public.inspection_centres` — the approved centres an inspector can
/// book.
///
/// Separate from [InspectionRepository] because it is a different question with a
/// different audience: this one is asked by an inspector who is choosing where to
/// send a car, and it is not scoped to a request at all. `inspection_centres` is
/// the second of the two tables readable by any signed-in user, since a centre is
/// chosen before the request has an inspector and so has no participant to test
/// against.
///
/// Only ever read. A centre's fee is a price the buyer is shown and approves, so
/// it is seeded by migration and administered by the service role; there is no
/// client INSERT, UPDATE or DELETE policy to be given a method for.
class CentreRepository {
  CentreRepository(this._client);

  final SupabaseClient _client;

  static const String _table = 'inspection_centres';

  /// The centres in one city, for the booking form's dropdown.
  ///
  /// Takes the city as a parameter because the caller is the one that knows it:
  /// it is the inspector's own `location_city`, which the profile is the only
  /// authority on. Filtering here rather than trusting the dropdown to have been
  /// filtered is what makes the booking form correct after a profile city change
  /// — and a centre in another city is a different appointment, not a different
  /// choice, so the list would be wrong rather than merely long.
  ///
  /// Ordered by fee then name so the cheapest centre is the first thing offered.
  /// An inspector is choosing on the buyer's behalf and the buyer's invoice
  /// carries the figure, so the price ordering is the one that is defensible; the
  /// name is the tiebreak because two centres at the same price are a matter of
  /// taste, not of arithmetic.
  Future<List<InspectionCentre>> listForCity(String city) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(_table)
          .select()
          .eq('city', city)
          .order('fee', ascending: true)
          .order('name', ascending: true);

      return rows.map(InspectionCentre.fromRow).toList();
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('centre list failed', error, stackTrace, {
        'city': city,
      });
      throw const InspectionFailure('Could not load the inspection centres.');
    }
  }
}
