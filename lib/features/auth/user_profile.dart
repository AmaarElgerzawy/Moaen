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
          other.rating == rating;

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
  );

  @override
  String toString() => 'UserProfile($id, $role, $locationCity)';
}
