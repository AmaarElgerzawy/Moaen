import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/pricing/commission.dart';
import '../../auth/user_profile.dart';
import '../../inspections/domain/inspection_centre.dart';
import '../domain/financial_overview.dart';
import '../domain/order_summary.dart';

/// Why an admin write was refused.
///
/// A closed set rather than a message, for the reason `AuthFailureReason` is one:
/// the presentation layer resolves the words from the ARB files, so an Arabic
/// admin panel shows an Arabic sentence. [message] is the English fallback and the
/// log's copy.
enum AdminFailureReason {
  /// Nothing specific to say.
  unknown,

  /// The write was refused by a policy — most often because the session is not an
  /// admin at all, which is worth saying plainly rather than as a generic error.
  notPermitted,

  /// This account's verification flags may only be written by an admin, and the
  /// caller is not one. The database says so by name.
  notAnAdmin,

  /// An inspector cannot be approved with no document on file.
  noDocumentOnFile,

  /// A rejection was submitted with no reason. The rule is the admin's own — a
  /// rejection the inspector cannot read is not a decision — so it is refused here
  /// where the text is, rather than by a database constraint that would reject
  /// every other caller of the column too.
  rejectionReasonRequired,

  /// The commission value is outside what the settings table accepts.
  commissionOutOfRange,
}

/// An administrative write that failed.
class AdminFailure implements Exception {
  const AdminFailure(
    this.message, {
    this.reason = AdminFailureReason.unknown,
    this.detail,
  });

  final String message;
  final AdminFailureReason reason;

  /// The server's own wording, for the log only.
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message ($detail)';
}

/// Every administrative read and write.
///
/// One class rather than five, and not for brevity: the five sections of the panel
/// have nothing in common except that they are only reachable by an admin, and
/// splitting them would mean five classes each with its own copy of "log it, then
/// say something the user can act on". The methods are grouped by section so a
/// reader can still find the right one.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  static const String _users = 'users';
  static const String _centres = 'inspection_centres';
  static const String _settings = 'platform_settings';

  // --- 1. Inspector verification --------------------------------------------

  /// Inspectors an admin has to do something about.
  ///
  /// Ordered unverified-first, then by age, so the account that has been waiting
  /// longest is the top of the queue and the newly-signed-up one is not.
  ///
  /// [includeApproved] defaults to false: the working list is what needs a
  /// decision, and the panel's second tab is for the ones already approved. An
  /// admin who wants the full roster flips the flag rather than scrolling past
  /// everyone who has already been handled.
  Future<List<UserProfile>> reviewQueue({bool includeApproved = false}) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(_users)
          .select()
          .eq('role', 'inspector')
          .order('is_approved', ascending: true)
          .order('created_at', ascending: true)
          .limit(_maxReviewRows);

      if (includeApproved) return rows.map(UserProfile.fromRow).toList();

      return rows
          .map(UserProfile.fromRow)
          .where((UserProfile profile) => !profile.isApproved)
          .toList();
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('review queue load failed', error, stackTrace);
      throw const AdminFailure('Could not load the inspector queue.');
    }
  }

  /// Approves an inspector.
  ///
  /// Refuses an inspector with no document on file. That check belongs here rather
  /// than only in the UI: the migration's trigger deliberately does *not* enforce
  /// it, because the grandfathered inspectors migration 0011 admits are approved
  /// with no photograph, and a trigger that refused them would break its own
  /// backfill. So the rule lives at the write that is actually about reviewing a
  /// document — and it can be moved into the trigger the day every account has one.
  ///
  /// Clears any previous rejection reason, so an inspector who was turned down and
  /// has been accepted is no longer shown as rejected. `queue_admin_notification`
  /// fires on the false → true edge and nothing else, so a re-approval of an
  /// already-approved inspector does not mail them again.
  Future<void> approve(String userId) async {
    try {
      await _client.from(_users).update(<String, dynamic>{
        'is_approved': true,
        'rejection_reason': null,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('approve failed', error, stackTrace, {
        'user_id': userId,
      });
      throw _failure(error, 'Could not approve this inspector.');
    }
  }

  /// Turns an inspector down, with a reason.
  ///
  /// Clears `is_approved` as well as writing the reason, so the two can never
  /// disagree: an account reading "approved, but here is why they were rejected"
  /// is not a state the product should be able to produce.
  ///
  /// The reason is shown to the inspector, so it is required rather than optional.
  /// A rejection with no explanation generates a support conversation that an admin
  /// then has to have individually, which is worse than making them type one line.
  Future<void> reject(String userId, String reason) async {
    final String trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw const AdminFailure(
        'Give a reason before rejecting an inspector.',
        reason: AdminFailureReason.rejectionReasonRequired,
      );
    }
    try {
      await _client.from(_users).update(<String, dynamic>{
        'is_approved': false,
        'rejection_reason': trimmed,
      }).eq('id', userId);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('reject failed', error, stackTrace, {
        'user_id': userId,
      });
      throw _failure(error, 'Could not record this decision.');
    }
  }

  // --- 2. Suspension ---------------------------------------------------------

  /// Every account, for the block/unblock list.
  ///
  /// Blocked rows are *not* filtered out here, which is the opposite of what the
  /// centre catalogue does and for the same reason in reverse: an admin's job on
  /// this screen is to find the suspended account and reverse it, so a list that
  /// hides them cannot be used for the one thing it exists for.
  Future<List<UserProfile>> listUsers({
    UserRole? role,
    bool onlyBlocked = false,
  }) async {
    try {
      PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
          .from(_users)
          .select();

      if (role != null) query = query.eq('role', role.name);
      if (onlyBlocked) query = query.eq('is_blocked', true);

      final List<Map<String, dynamic>> rows =
          await query.order('created_at', ascending: false).limit(_maxReviewRows);
      return rows.map(UserProfile.fromRow).toList();
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('user list failed', error, stackTrace);
      throw const AdminFailure('Could not load the accounts.');
    }
  }

  /// Suspends or restores an account.
  ///
  /// Takes the target state rather than a "toggle", because a toggle computed from
  /// a list the admin is looking at can be wrong: the list may be a filtered page of
  /// a larger roster, it may be stale, and pressing the wrong button would suspend
  /// an account that was fine. The screen reads the row's own flag to decide which
  /// button to draw, and sends the state that button means.
  ///
  /// `reason` is optional because a suspension is often immediate and
  /// unexplained; when one is given it is what the account's owner is shown.
  Future<void> setBlocked(
    String userId, {
    required bool blocked,
    String? reason,
  }) async {
    try {
      await _client.from(_users).update(<String, dynamic>{
        'is_blocked': blocked,
        'blocked_reason': blocked && reason != null && reason.trim().isNotEmpty
            ? reason.trim()
            : null,
      }).eq('id', userId);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('block toggle failed', error, stackTrace, {
        'user_id': userId,
        'blocked': blocked,
      });
      throw _failure(error, 'Could not change this account.');
    }
  }

  /// Every centre, suspended or not. See [listUsers] for why none are filtered.
  Future<List<InspectionCentre>> listCentres() async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(_centres)
          .select()
          .order('city')
          .order('name')
          .limit(_maxReviewRows);
      return rows.map(InspectionCentre.fromRow).toList();
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('centre list failed', error, stackTrace);
      throw const AdminFailure('Could not load the centres.');
    }
  }

  /// Suspends or restores a centre.
  ///
  /// Enforced as a filter on the SELECT policy rather than as a trigger, so an
  /// existing booking keeps working: a suspension stops a centre being *offered*
  /// to an inspector, and it would be a considerable overreach for it to void a
  /// car already on its ramp.
  Future<void> setCentreBlocked(String centreId, {required bool blocked}) async {
    try {
      await _client
          .from(_centres)
          .update(<String, dynamic>{'is_blocked': blocked})
          .eq('id', centreId);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('centre block failed', error, stackTrace, {
        'centre_id': centreId,
      });
      throw _failure(error, 'Could not change this centre.');
    }
  }

  // --- 3. Financial overview -------------------------------------------------

  /// The money, as one row.
  ///
  /// Reads the `admin_financial_overview` view, which is `security_invoker` — so
  /// this query is subject to the `payments` policies, and an admin is the only
  /// caller that sees anybody else's rows. The arithmetic is in the database; a
  /// second copy of it here would be a second thing to get wrong.
  Future<FinancialOverview> financials() async {
    try {
      final List<Map<String, dynamic>> rows =
          await _client.from('admin_financial_overview').select().limit(1);
      if (rows.isEmpty) return const FinancialOverview();
      return FinancialOverview.fromRow(rows.first);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('financial overview failed', error, stackTrace);
      throw const AdminFailure('Could not load the financial overview.');
    }
  }

  /// Orders grouped by status, from the `admin_order_summary` view.
  Future<List<OrderSummary>> orderSummary() async {
    try {
      final List<Map<String, dynamic>> rows =
          await _client.from('admin_order_summary').select();
      final List<OrderSummary> summary =
          rows.map(OrderSummary.fromRow).toList();
      summary.sort((OrderSummary a, OrderSummary b) =>
          a.status.compareTo(b.status));
      return summary;
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('order summary failed', error, stackTrace);
      throw const AdminFailure('Could not load the order summary.');
    }
  }

  // --- 5. Commission ---------------------------------------------------------

  /// Writes the platform commission.
  ///
  /// The write lives here and the read does not, because "who may change this" and
  /// "who may quote this" are different questions: `platform_settings`'s policy
  /// admits an admin and nobody else, while every buyer and every inspector has to be
  /// able to *read* the value in order to be shown a price. See
  /// `core/pricing/commission_repository.dart`.
  ///
  /// Validated here as well as by the table's check constraints. The table is the
  /// authority — it is what every request's snapshot is computed from — but a
  /// percent above 100 should be refused by the form that sets it, with the field
  /// highlighted, rather than by a `23514` after the admin has navigated away.
  Future<void> setCommission(Commission commission) async {
    if (commission.value < 0) {
      throw const AdminFailure(
        'The commission cannot be negative.',
        reason: AdminFailureReason.commissionOutOfRange,
      );
    }
    if (commission.type == CommissionType.percent && commission.value > 100) {
      throw const AdminFailure(
        'A percentage cannot be above 100.',
        reason: AdminFailureReason.commissionOutOfRange,
      );
    }
    try {
      await _client.from(_settings).update(commission.toRow()).eq('id', true);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('commission write failed', error, stackTrace);
      throw _failure(error, 'Could not save the commission.');
    }
  }

  // --- Notifications ---------------------------------------------------------

  /// Notifications an admin's actions have queued but nobody has sent.
  ///
  /// Read-only, and the panel shows the count. If the edge function is not
  /// deployed the number here is the honest answer to "did those inspectors get
  /// told", which is exactly the question an outbox exists to make answerable.
  Future<int> pendingNotifications() async {
    try {
      // `is` is a keyword in Dart, so the filter goes through [isFilter], which is
      // spelled out rather than hidden behind a helper that would read as a method
      // this repository owns.
      final List<Map<String, dynamic>> rows = await _client
          .from('admin_notifications')
          .select('id')
          .filter('delivered_at', 'is', null);
      return rows.length;
    } on PostgrestException catch (error, stackTrace) {
      // Not a failure the panel should surface. A missing grant on
      // `admin_notifications` is a deployment detail, and the section that asked
      // is the notification count — which is worth showing as unknown rather than
      // hiding an entire screen behind it.
      AppLogger.instance.error('notification count failed', error, stackTrace);
      return 0;
    }
  }

  /// Maps a database refusal onto something a person can act on.
  static AdminFailure _failure(PostgrestException error, String fallback) {
    AppLogger.instance.debug('admin error detail', {
      'raw': error.message,
      'code': error.code,
    });

    if (error.code == '42501') {
      final bool aboutFlags = error.message.contains(
        'verification and suspension',
      );
      return AdminFailure(
        aboutFlags ? 'Only an administrator can do that.' : 'Not allowed.',
        reason: aboutFlags
            ? AdminFailureReason.notAnAdmin
            : AdminFailureReason.notPermitted,
        detail: error.message,
      );
    }
    if (error.code == '23514') {
      return AdminFailure(
        'That value was rejected by the server.',
        reason: AdminFailureReason.commissionOutOfRange,
        detail: error.message,
      );
    }
    return AdminFailure(fallback, detail: error.message);
  }

  /// The ceiling on a roster or catalogue read. See [listUsers].
  static const int _maxReviewRows = 300;
}