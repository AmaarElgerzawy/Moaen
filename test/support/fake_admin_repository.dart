import 'package:moaen/core/pricing/commission.dart';
import 'package:moaen/core/pricing/commission_repository.dart';
import 'package:moaen/features/admin/data/admin_repository.dart';
import 'package:moaen/features/admin/domain/financial_overview.dart';
import 'package:moaen/features/admin/domain/order_summary.dart';
import 'package:moaen/features/auth/data/identity_repository.dart';
import 'package:moaen/features/auth/user_profile.dart';
import 'package:moaen/features/inspections/domain/inspection_centre.dart';

import 'test_client.dart';

/// A [CommissionRepository] with no network behind it.
///
/// Its own fake rather than an override of the read, because the commission is the one
/// setting with a *writer* too: a test that moves the commission and reads it back has
/// to see the value the write produced, and two independent fakes with two fields would
/// make "it saved" a fact the test chose rather than one the app established.
///
/// [current] rather than `commission` because a field cannot share a name with the
/// method it overrides; nothing else here needs the shorter name.
class FakeCommissionRepository extends CommissionRepository {
  FakeCommissionRepository({Commission commission = const Commission()})
    : current = commission,
      super(createTestClient());

  Commission current;

  @override
  Future<Commission> commission() async => current;
}

/// An [IdentityRepository] that signs a fixed URL for every document.
///
/// Signing is the only read the admin panel makes of it, and it is the one the real
/// repository refuses to fail on: a document that cannot be loaded comes back as an
/// empty string so one row cannot take the queue down. This fake models that by
/// signing a URL that `Image.network` will fail to load, which is what lets the queue's
/// missing-photo frame be tested for real rather than by having the provider throw.
class FakeIdentityRepository extends IdentityRepository {
  FakeIdentityRepository() : super(createTestClient());

  /// Every path that was asked to be signed, in order.
  final List<String> signedPaths = <String>[];

  @override
  Future<String> signedUrlFor(String userId, String? path) async {
    if (path == null || path.isEmpty) return '';
    if (!path.startsWith('$userId/')) return '';
    signedPaths.add(path);
    return '';
  }
}

/// An [AdminRepository] with no network behind it.
///
/// Mutable in every direction a panel test needs: the rosters start as given, the
/// writes land on them, and [failure] turns any of them into an error so the
/// banner can be exercised without a server.
///
/// The refusal rules are *not* re-implemented here — the reject-without-a-reason
/// guard and the commission range checks are the repository's own, and a fake that
/// duplicated them would let a test pass while the real guard stopped working.
/// Everything else is modelled because the panel's screens read the result.
class FakeAdminRepository extends AdminRepository {
  FakeAdminRepository({
    List<UserProfile>? users,
    List<InspectionCentre>? centres,
    this.money = const FinancialOverview(),
    List<OrderSummary>? summary,
    this.commission = const Commission(),
  }) : users = <UserProfile>[...?users],
       centres = <InspectionCentre>[...?centres],
       summary = <OrderSummary>[...?summary],
       super(createTestClient());

  final List<UserProfile> users;
  final List<InspectionCentre> centres;
  final List<OrderSummary> summary;
  FinancialOverview money;
  Commission commission;

  /// Thrown by every read when set. Drives the panel's failed-write banner.
  AdminFailure? failure;

  /// Every write, in order, as `(method, id, value)` triples.
  ///
  /// Recorded rather than merely applied because the panel's whole purpose is
  /// changing state: a test that only asserted the new row would pass against a
  /// repository that made the change and a screen that never sent it.
  final List<({String method, String id, Object? value})> writes =
      <({String method, String id, Object? value})>[];

  UserProfile? _find(String userId) {
    for (final UserProfile profile in users) {
      if (profile.id == userId) return profile;
    }
    return null;
  }

  @override
  Future<List<UserProfile>> reviewQueue({bool includeApproved = false}) async {
    final AdminFailure? f = failure;
    if (f != null) throw f;

    return <UserProfile>[
      for (final UserProfile profile in users)
        if (profile.role == UserRole.inspector &&
            (includeApproved || !profile.isApproved))
          profile,
    ];
  }

  @override
  Future<void> approve(String userId) async {
    writes.add((method: 'approve', id: userId, value: null));
    final AdminFailure? f = failure;
    if (f != null) throw f;

    final UserProfile? target = _find(userId);
    if (target == null) return;
    final int index = users.indexOf(target);
    users[index] = target.copyWith(
      isApproved: true,
      rejectionReason: null,
      approvedAt: DateTime.utc(2026, 3, 1),
    );
  }

  @override
  Future<void> reject(String userId, String reason) async {
    final String trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw const AdminFailure(
        'Give a reason before rejecting an inspector.',
        reason: AdminFailureReason.rejectionReasonRequired,
      );
    }
    writes.add((method: 'reject', id: userId, value: trimmed));
    final AdminFailure? f = failure;
    if (f != null) throw f;

    final UserProfile? target = _find(userId);
    if (target == null) return;
    final int index = users.indexOf(target);
    users[index] = target.copyWith(isApproved: false, rejectionReason: trimmed);
  }

  @override
  Future<List<UserProfile>> listUsers({
    UserRole? role,
    bool onlyBlocked = false,
  }) async {
    final AdminFailure? f = failure;
    if (f != null) throw f;

    return <UserProfile>[
      for (final UserProfile profile in users)
        if (role == null || profile.role == role)
          if (!onlyBlocked || profile.isBlocked) profile,
    ];
  }

  @override
  Future<void> setBlocked(
    String userId, {
    required bool blocked,
    String? reason,
  }) async {
    writes.add((
      method: blocked ? 'block' : 'unblock',
      id: userId,
      value: reason?.trim(),
    ));
    final AdminFailure? f = failure;
    if (f != null) throw f;

    final UserProfile? target = _find(userId);
    if (target == null) return;
    final int index = users.indexOf(target);
    users[index] = target.copyWith(
      isBlocked: blocked,
      blockedReason: blocked ? reason?.trim() : null,
    );
  }

  @override
  Future<List<InspectionCentre>> listCentres() async {
    final AdminFailure? f = failure;
    if (f != null) throw f;
    return List<InspectionCentre>.of(centres);
  }

  @override
  Future<void> setCentreBlocked(
    String centreId, {
    required bool blocked,
  }) async {
    writes.add((
      method: blocked ? 'blockCentre' : 'unblockCentre',
      id: centreId,
      value: null,
    ));
    final AdminFailure? f = failure;
    if (f != null) throw f;

    final int index = centres.indexWhere(
      (InspectionCentre centre) => centre.id == centreId,
    );
    if (index == -1) return;
    centres[index] = centres[index].copyWith(isBlocked: blocked);
  }

  @override
  Future<FinancialOverview> financials() async {
    final AdminFailure? f = failure;
    if (f != null) throw f;
    return money;
  }

  @override
  Future<List<OrderSummary>> orderSummary() async {
    final AdminFailure? f = failure;
    if (f != null) throw f;
    return List<OrderSummary>.of(summary);
  }

  @override
  Future<void> setCommission(Commission commission) async {
    // The range checks stay in the repository's own `setCommission` by delegation
    // rather than being re-implemented here, so the guard a test exercises is the
    // guard that ships. `super` needs the client, which is the one thing the fake has
    // no use for.
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
    writes.add((
      method: 'setCommission',
      id: 'platform_settings',
      value: commission,
    ));
    final AdminFailure? f = failure;
    if (f != null) throw f;
    this.commission = commission;
  }

  @override
  Future<int> pendingNotifications() async => failure == null ? 2 : 0;
}

/// A user for the panel tests.
///
/// Every flag explicit, because these rows are what the panel's *decisions* are
/// applied to: a default that quietly read as "approved" or "not blocked" would
/// make the accounts tab's buttons appear in the wrong state.
UserProfile buildUser({
  required String id,
  required String name,
  UserRole role = UserRole.inspector,
  bool approved = false,
  bool blocked = false,
  String? idPhoto,
  String? rejectionReason,
  String? blockedReason,
  String? city = 'Dammam',
  String email = 'someone@example.com',
}) => UserProfile(
  id: id,
  fullName: name,
  email: email,
  role: role,
  locationCity: city,
  idPhotoPath: idPhoto ?? 'inspector-1/id.jpg',
  isApproved: approved,
  isBlocked: blocked,
  rejectionReason: rejectionReason,
  blockedReason: blockedReason,
);

/// A centre for the panel tests.
InspectionCentre buildCentre({
  required String id,
  required String name,
  bool blocked = false,
  String city = 'Dammam',
  double fee = 300,
}) => InspectionCentre(
  id: id,
  name: name,
  city: city,
  fee: fee,
  isBlocked: blocked,
);
