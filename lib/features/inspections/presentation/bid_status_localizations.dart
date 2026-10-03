import 'package:flutter/widgets.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../domain/inspection_bid.dart';

/// Localised names for [BidStatus].
///
/// The words live here rather than on the enum because an enum cannot reach the
/// localisation delegates without a `BuildContext`, and a hard-coded English string
/// on a domain type is how an Arabic app ends up with English leaking out of it in
/// exactly one place — the one place nobody looks for it.
///
/// Exhaustive over the enum on purpose: adding a fourth status to the database and
/// to `BidStatus` stops this from compiling rather than quietly rendering nothing.
///
/// [BidStatus.none] has no label and returns null. "No negotiation happened" is not a
/// state a card announces; it is the absence of one, and printing it would put a
/// badge on every ordinary job.
extension LocalizedBidStatus on BidStatus {
  String? localizedName(BuildContext context) => switch (this) {
    BidStatus.none => null,
    BidStatus.pending => AppLocalizations.of(context).bidStatusPending,
    BidStatus.agreed => AppLocalizations.of(context).bidStatusAgreed,
    BidStatus.declined => AppLocalizations.of(context).bidStatusDeclined,
  };
}