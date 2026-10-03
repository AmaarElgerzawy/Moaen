/// The three system roles, mirroring the `user_role` enum in the database.
///
/// Display names live in [LocalizedUserRole] rather than here. An enum cannot
/// reach the localisation delegates without a `BuildContext`, and hard-coding
/// English strings on a domain type is how an Arabic app ends up with English
/// leaking out of it in exactly one place.
enum UserRole {
  client,
  inspector,
  admin;

  static UserRole fromName(String value) => UserRole.values.firstWhere(
    (UserRole role) => role.name == value,
    orElse: () => UserRole.client,
  );
}

/// A row of `public.users`.
///
/// The id is the Supabase Auth user id; there is no separate primary key on the
/// client side, so the two can never drift.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.phone = '',
    this.avatarUrl,
    this.locationCity,
    this.rating = 0,
    this.idPhotoPath,
    this.isApproved = false,
    this.isBlocked = false,
    this.approvedAt,
    this.rejectionReason,
    this.blockedReason,
  });

  factory UserProfile.fromRow(Map<String, dynamic> row) {
    final Object? rawRating = row['rating'];
    return UserProfile(
      id: row['id'] as String,
      fullName: row['full_name'] as String? ?? '',
      email: row['email'] as String? ?? '',
      phone: row['phone'] as String? ?? '',
      role: UserRole.fromName(row['role'] as String? ?? 'client'),
      avatarUrl: row['avatar_url'] as String?,
      locationCity: row['location_city'] as String?,
      rating: rawRating is num ? rawRating.toDouble() : 0,
      idPhotoPath: row['id_photo_url'] as String?,
      isApproved: row['is_approved'] == true,
      isBlocked: row['is_blocked'] == true,
      approvedAt: row['approved_at'] == null
          ? null
          : DateTime.parse(row['approved_at'] as String),
      rejectionReason: row['rejection_reason'] as String?,
      blockedReason: row['blocked_reason'] as String?,
    );
  }

  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String? avatarUrl;

  final UserRole role;

  /// The city this inspector serves. Null for clients, and the reason an
  /// inspector without a city sees an empty job board rather than every job.
  final String? locationCity;

  final double rating;

  /// Object path in the private `identity-documents` bucket, not a URL.
  ///
  /// A path rather than a signed URL because the bucket is private and a URL
  /// pasted into a profile is a bearer token with a one-hour expiry that looks
  /// permanent. The URL is minted per read, by `IdentityRepository`.
  ///
  /// Null means no document on file — which is a real state, not a missing value:
  /// an inspector can sign up and be waiting for their upload to land.
  final String? idPhotoPath;

  /// Whether an admin has verified this inspector.
  ///
  /// Meaningless for a client, who is provisioned approved and whose use of the
  /// platform never depended on it. Migration 0011 does not gate clients on this
  /// column anywhere.
  final bool isApproved;

  /// Whether an admin has suspended this account.
  ///
  /// Distinct from [isApproved] on purpose: an account can be perfectly verified
  /// and still be suspended, and an account can be un-approved and never have
  /// been blocked. Conflating them would mean un-suspending an inspector also
  /// silently re-opened the job board.
  final bool isBlocked;

  /// When the account was last approved, for the admin's roster.
  ///
  /// Null for an account that has never been approved, and for a client — the
  /// column is written only by an approval, and a client is provisioned approved
  /// without one. Shown rather than inferred, because "verified" with no date is
  /// indistinguishable from "verified and we do not know how long ago".
  final DateTime? approvedAt;

  /// Why an inspector was turned down. Null while they are merely unverified.
  final String? rejectionReason;

  /// Why an account was suspended. Null for every account not suspended.
  final String? blockedReason;

  /// Whether this account may do its job at all.
  ///
  /// One predicate rather than a chain of `if (role == ...)` at every call site,
  /// because the rule has two clauses and they differ by role: a buyer is usable
  /// the moment they sign up, and an inspector is not until an admin says so.
  ///
  /// [isBlocked] is checked first for every role. A suspended inspector who is
  /// also unverified is suspended, and the screen that says so should not also
  /// claim they are waiting for approval — the fix is different.
  bool get canOperate => !isBlocked && (role != UserRole.inspector || isApproved);

  /// Why [canOperate] is false, for the screen that explains it.
  ///
  /// An enum rather than a message, for the same reason `AuthFailure` is one: the
  /// words live in the ARB files, and a Dart string here would be the one place
  /// the Arabic build reads English.
  AccessBlock get accessBlock {
    if (isBlocked) return AccessBlock.suspended;
    if (role == UserRole.inspector && !isApproved) {
      return rejectionReason == null || rejectionReason!.isEmpty
          ? AccessBlock.awaitingApproval
          : AccessBlock.rejected;
    }
    return AccessBlock.none;
  }

  /// True when this inspector has nothing on file for an admin to review.
  ///
  /// The column's own meaning is "verified"; this is about the *document*. They
  /// are separate because migration 0011 grandfathers inspectors who were already
  /// working when the column was added, and those accounts are approved with no
  /// photograph. An admin's queue needs to be able to find them, so the panel
  /// filters on this rather than inventing a fourth status.
  bool get isAwaitingDocuments => idPhotoPath == null || idPhotoPath!.isEmpty;

  /// A copy with [locationCity] replaced, for the profile editor.
  ///
  /// The only field that is ever edited in place, so the copy is narrow; nothing
  /// else on a profile is user-mutable today. The verification flags are
  /// included because the admin screen edits them and reads a profile back after
  /// saving — dropping them here would make the row appear unverified for one
  /// frame after every approval.
  UserProfile copyWith({
    String? locationCity,
    String? idPhotoPath,
    bool? isApproved,
    bool? isBlocked,
    DateTime? approvedAt,
    String? rejectionReason,
    String? blockedReason,
  }) => UserProfile(
    id: id,
    fullName: fullName,
    email: email,
    phone: phone,
    avatarUrl: avatarUrl,
    role: role,
    locationCity: locationCity ?? this.locationCity,
    rating: rating,
    idPhotoPath: idPhotoPath ?? this.idPhotoPath,
    isApproved: isApproved ?? this.isApproved,
    isBlocked: isBlocked ?? this.isBlocked,
    approvedAt: approvedAt ?? this.approvedAt,
    rejectionReason: rejectionReason ?? this.rejectionReason,
    blockedReason: blockedReason ?? this.blockedReason,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          other.id == id &&
          other.fullName == fullName &&
          other.email == email &&
          other.phone == phone &&
          other.avatarUrl == avatarUrl &&
          other.role == role &&
          other.locationCity == locationCity &&
          other.rating == rating &&
          other.idPhotoPath == idPhotoPath &&
          other.isApproved == isApproved &&
          other.isBlocked == isBlocked &&
          other.approvedAt == approvedAt &&
          other.rejectionReason == rejectionReason &&
          other.blockedReason == blockedReason;

  @override
  int get hashCode => Object.hash(
    id,
    fullName,
    email,
    phone,
    avatarUrl,
    role,
    locationCity,
    rating,
    idPhotoPath,
    isApproved,
    isBlocked,
    approvedAt,
    rejectionReason,
    blockedReason,
  );

  @override
  String toString() =>
      'UserProfile($id, $role, approved: $isApproved, blocked: $isBlocked)';
}

/// Why an account cannot use the platform. The localisation tables name these.
enum AccessBlock {
  /// Nothing is wrong. Not a failure state; present so a caller can switch on one
  /// value instead of testing two booleans.
  none,

  /// An inspector waiting for an admin to review their documents.
  awaitingApproval,

  /// An inspector an admin turned down, with a reason.
  rejected,

  /// Suspended by an admin.
  suspended,
}
