import 'package:flutter/widgets.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../data/admin_repository.dart';

/// Localised sentences for [AdminFailure].
///
/// The same arrangement as `LocalizedUserRole` and `LocalizedBidStatus`: a domain
/// type carries a reason, and the words live in the ARB files. The English
/// `AdminFailure.message` exists for the log and for tests, and is never rendered.
extension LocalizedAdminFailure on AdminFailure {
  String localizedMessage(BuildContext context) =>
      localizedAdminReason(context, reason);
}

/// The sentence for one [AdminFailureReason].
///
/// A free function as well as an extension so a screen holding only a reason — a
/// catch that never had an [AdminFailure] object — can ask the same question. The two
/// must not drift, so the extension delegates here rather than repeating the switch.
String localizedAdminReason(BuildContext context, AdminFailureReason reason) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return switch (reason) {
    AdminFailureReason.notPermitted => l10n.adminErrorNotPermitted,
    AdminFailureReason.notAnAdmin => l10n.adminErrorNotAnAdmin,
    AdminFailureReason.noDocumentOnFile => l10n.adminErrorNoDocument,
    AdminFailureReason.rejectionReasonRequired => l10n.adminRejectPrompt,
    AdminFailureReason.commissionOutOfRange => l10n.adminCommissionErrorRange,
    AdminFailureReason.unknown => l10n.errorGeneric,
  };
}