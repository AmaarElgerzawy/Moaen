import '../../l10n/gen/app_localizations.dart';
import 'auth_repository.dart';

/// Localised sentences for [AuthFailure].
///
/// Exhaustive over [AuthFailureReason] on purpose: a new reason stops the build
/// rather than reaching a user as an empty banner, which on this screen would
/// be indistinguishable from no banner at all.
///
/// [AuthFailure.detail] is deliberately not reachable from here. It is the
/// server's own wording and goes to the log only.
extension LocalizedAuthFailure on AuthFailure {
  String localizedMessage(AppLocalizations l10n) => switch (reason) {
    AuthFailureReason.invalidCredentials => l10n.authErrorInvalidCredentials,
    AuthFailureReason.emailNotConfirmed => l10n.authErrorEmailNotConfirmed,
    AuthFailureReason.alreadyRegistered => l10n.authErrorAlreadyRegistered,
    AuthFailureReason.signupsDisabled => l10n.authErrorSignupsDisabled,
    AuthFailureReason.providerDisabled => l10n.authErrorProviderDisabled,
    AuthFailureReason.rateLimited => l10n.authErrorRateLimited,
    AuthFailureReason.profileUnavailable => l10n.authErrorProfileUnavailable,
    AuthFailureReason.noAccountReturned => l10n.authErrorNoAccount,
    AuthFailureReason.confirmationRequired => l10n.authErrorConfirmEmail,
    AuthFailureReason.signOutFailed => l10n.authErrorSignOutFailed,
    AuthFailureReason.unrecognised => l10n.errorGeneric,
  };
}
