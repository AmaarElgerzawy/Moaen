import 'package:flutter/widgets.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection_draft.dart' show CostEstimate;

/// The ceiling quoted in the amount-range sentence.
///
/// [CostEstimate.maxBudget] — the same bound `car_inspections.price` carries — rather
/// than a number written here. A range message that disagreed with the column would
/// tell an inspector a limit the database does not have.
String _maxAmount(BuildContext context) =>
    '${CostEstimate.maxBudget.round()}';

/// Localised sentences for [InspectionFailure].
///
/// A screen shows [localizedInspectionFailure] for a buyer's answer and
/// [localizedOfferFailure] for an inspector's counter-offer. Two functions rather
/// than one taking a flag, because the *fallback* differs: a buyer's "something went
/// wrong" is `bidErrorGeneric` and an inspector's is `bidErrorSubmit`, and a shared
/// fallback would have to be a third sentence that fits neither as well as the
/// specific one does.
///
/// The English `InspectionFailure.message` is the log's copy and is never rendered.
/// That is the whole reason [InspectionFailureReason] exists: a PostgREST error names
/// tables and columns, which is not something to show somebody trying to book a car
/// inspection, and the sentences a user can act on have to come from the ARB files
/// or an Arabic build would show them in English.
String localizedInspectionFailure(BuildContext context, InspectionFailureReason reason) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return switch (reason) {
    InspectionFailureReason.noOfferToRespondTo => l10n.bidErrorNoOffer,
    InspectionFailureReason.notTheAssignedInspector => l10n.bidErrorNotYours,
    InspectionFailureReason.inspectionClosed => l10n.bidErrorClosed,
    InspectionFailureReason.amountOutOfRange =>
      l10n.bidErrorAmountRange(_maxAmount(context)),
    // `notYetClaimed` cannot happen on a buyer's answer — they are the only party who
    // answers, and answering requires an offer to exist — but mapping it to the
    // generic sentence rather than to an inspector's copy keeps the two functions
    // honest about the same enum.
    InspectionFailureReason.notYetClaimed ||
    InspectionFailureReason.network ||
    InspectionFailureReason.unknown => l10n.bidErrorGeneric,
  };
}

/// The sentence for a refused counter-offer.
String localizedOfferFailure(BuildContext context, InspectionFailureReason reason) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  return switch (reason) {
    InspectionFailureReason.notYetClaimed => l10n.bidErrorAlreadyClaimed,
    InspectionFailureReason.notTheAssignedInspector => l10n.bidErrorNotAssigned,
    InspectionFailureReason.amountOutOfRange =>
      l10n.bidErrorAmountRange(_maxAmount(context)),
    InspectionFailureReason.inspectionClosed => l10n.bidErrorClosed,
    InspectionFailureReason.noOfferToRespondTo ||
    InspectionFailureReason.network ||
    InspectionFailureReason.unknown => l10n.bidErrorSubmit,
  };
}

/// The sentence for an [InspectionFailure] itself, for a caller holding the object.
extension LocalizedInspectionFailure on InspectionFailure {
  String localizedMessage(BuildContext context) =>
      localizedInspectionFailure(context, reason);
}