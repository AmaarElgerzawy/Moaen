import 'package:flutter/widgets.dart';

import '../../l10n/gen/app_localizations.dart';
import 'user_profile.dart';

/// Localised display names for [UserRole].
///
/// The mapping is exhaustive over the enum on purpose. If a fourth role is added
/// to the database and the enum, this stops compiling rather than quietly
/// rendering an empty label to a user.
extension LocalizedUserRole on UserRole {
  String localizedName(BuildContext context) => switch (this) {
    UserRole.client => AppLocalizations.of(context).roleClient,
    UserRole.inspector => AppLocalizations.of(context).roleInspector,
    UserRole.admin => AppLocalizations.of(context).roleAdmin,
  };

  /// The shorter phrasing used where the role is being chosen rather than
  /// described — "I am buying" rather than "Car buyer".
  String localizedPrompt(BuildContext context) => switch (this) {
    UserRole.client => AppLocalizations.of(context).rolePickClient,
    UserRole.inspector => AppLocalizations.of(context).rolePickInspector,
    // No prompt exists for admin because it is not self-assignable (D4), so
    // there is no screen that offers the choice. Falls back to the name.
    UserRole.admin => AppLocalizations.of(context).roleAdmin,
  };
}
