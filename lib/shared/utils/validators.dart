/// Input validation shared by the auth forms.
///
/// Kept as plain functions rather than form-field objects so the rules are
/// unit-testable without pumping a widget, and so the sign-up and sign-in
/// screens cannot disagree about what a valid password is.
abstract final class Validators {
  /// Deliberately permissive. The authoritative check is the confirmation
  /// email; a pattern strict enough to reject a valid address costs more in
  /// support than it saves.
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static final RegExp _phone = RegExp(r'^\+?[0-9]{6,20}$');

  /// Length only. Composition rules push people toward predictable passwords,
  /// which is the opposite of the intent.
  static const int minPasswordLength = 8;

  static String? email(String? value) {
    final String input = (value ?? '').trim();
    if (input.isEmpty) return 'Email is required';
    if (!_email.hasMatch(input)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters';
    }
    return null;
  }

  static String? fullName(String? value) {
    final String input = (value ?? '').trim();
    if (input.isEmpty) return 'Full name is required';
    if (input.length < 2) return 'Enter your full name';
    return null;
  }

  /// Optional field: an empty value is valid, a malformed one is not.
  static String? phone(String? value) {
    final String input = (value ?? '').trim();
    if (input.isEmpty) return null;
    if (!_phone.hasMatch(input)) return 'Enter a valid phone number';
    return null;
  }

  static String? city(String? value) {
    final String input = (value ?? '').trim();
    if (input.isEmpty) return 'Service city is required for inspectors';
    if (input.length < 2) return 'Enter a valid city name';
    return null;
  }
}
