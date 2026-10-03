import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/inspection_controller.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection_bid.dart';
import '../domain/inspection_draft.dart';
import '../domain/inspection_request.dart';
import 'bid_status_localizations.dart';
import 'inspection_failure_localizations.dart';
import 'widgets/design_widgets.dart';

/// The buyer's card for a counter-offer: the split, and the two answers.
///
/// Its own loading state rather than the page's shared request controller, because the
/// write this fires is a *bid* and the request controller's spinner belongs to the
/// cancel button at the foot of the page. Two spinners on one screen, one of which
/// belongs to a button forty pixels away from the thing that is actually running, is
/// a screen where the reader cannot tell which action they are waiting on.
class BuyerOfferCard extends ConsumerWidget {
  const BuyerOfferCard({required this.request, super.key});

  final InspectionRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionBid>> offers = ref.watch(
      inspectionOffersProvider(request.id),
    );
    final bool busy = ref.watch(bidControllerProvider).isLoading;

    // One [BidSummary] for both cards on this page, so the offer's total and the
    // settled total cannot be derived by two different pieces of code.
    final BidSummary summary = BidSummary.of(
      request,
      offers: offers.value ?? const <InspectionBid>[],
    );

    // Only an open offer is a question. Every other state is either settled — and
    // belongs in the invoice below, which reads the agreed figures — or absent, and
    // absence is not worth a card.
    final InspectionBid? open = summary.openOffer;
    if (open == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: NoticeBox(
        titleIcon: Icons.handshake_outlined,
        title: l10n.bidBuyerPrompt(
          CostEstimate.format(open.totalAmount),
          CostEstimate.format(summary.budget),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The split, not the offer's total alone. A buyer deciding whether to
            // accept 249 instead of 200 is deciding about the fee inside it, and a
            // single number would ask them to take the platform's cut on trust.
            _Split(
              net: open.netAmount,
              fee: open.platformFee,
              total: open.totalAmount,
            ),
            if (open.note.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              // What the inspector said with the number. An inspector offering 200
              // instead of 451 is usually saying "this car needs a full day", and a
              // buyer only learns that from a sentence, not from the difference.
              Text(open.note, style: AppText.secondary(12)),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () =>
                              _answer(context, ref, open: open, accept: false),
                    child: Text(l10n.bidKeepOffer),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: busy
                        ? null
                        : () => _answer(context, ref, open: open, accept: true),
                    // Not `actionAccept`, which reads "Accept inspection" and belongs
                    // to the inspector's claim button: this button agrees to a price,
                    // and a buyer being asked to "accept the inspection" is being
                    // asked about the wrong thing.
                    child: Text(l10n.bidAcceptOffer),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _answer(
    BuildContext context,
    WidgetRef ref, {
    required InspectionBid open,
    required bool accept,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? note = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => _ReasonDialog(accepting: accept),
    );

    // A null return is a dismissal, and a dismissal is not a refusal. Refusing is a
    // statement about somebody's price, so it takes a tap: `seal_bid` will happily
    // accept a refusal with no reason, and the UI should not let a stray dialog
    // dismissal land as one.
    if (note == null) return;

    try {
      await ref
          .read(bidControllerProvider.notifier)
          .respond(inspectionId: request.id, accept: accept, note: note);
    } on InspectionFailure catch (failure) {
      if (!context.mounted) return;
      _show(context, localizedInspectionFailure(context, failure.reason));
      return;
    } on Object {
      if (!context.mounted) return;
      _show(context, l10n.errorGeneric);
      return;
    }

    if (!context.mounted) return;
    _show(
      context,
      accept
          // The offer's own total, not the buyer's budget. Announcing "agreed at 500"
          // after the buyer accepted 249 would tell them the negotiation was
          // pointless — and it is the total that `enforce_bidding` freezes, so it is
          // the number that will be invoiced.
          ? l10n.bidAcceptedNotice(CostEstimate.format(open.totalAmount))
          : l10n.bidDeclinedNotice,
    );
  }

  void _show(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The buyer's one line on a refusal, handed back to the inspector.
///
/// Offered on both answers rather than only on a refusal: an inspector reading "she
/// accepted" learns nothing, and the field costs one keystroke to leave empty. Making
/// it refusal-only would have been defensible; making it required would not.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.accepting});

  final bool accepting;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(widget.accepting ? l10n.bidAcceptOffer : l10n.bidKeepOffer),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _reason,
            minLines: 1,
            maxLines: 3,
            // An admin writes this in whichever language their inspector reads, so it
            // is left to the field's own bidi rather than forced to the screen's.
            textAlign: TextAlign.start,
            decoration: InputDecoration(
              labelText: l10n.bidBuyerReason,
              helperText: l10n.bidBuyerReasonHint,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text(
            widget.accepting ? l10n.bidAcceptOffer : l10n.bidKeepOffer,
          ),
        ),
      ],
    );
  }
}

/// The two sides of a negotiation, written once.
///
/// Both cards in this file read the same offers list and both are shown the *same*
/// pair of numbers — the inspector's net and the buyer's total — because the whole
/// safety of the arrangement is that neither party can set either number. If the buyer
/// computed the total by adding the fee themselves, a stale `platform_settings` read
/// would put a total on screen that the database is about to refuse; if the inspector
/// computed their net the same way, a percentage commission would round differently on
/// the way in. So both figures come from [BidSummary], which reads the sealed offer,
/// and neither card does arithmetic on them.
///
/// Where the two sides differ is the *verb*: the inspector may send another offer, the
/// buyer may answer the one standing. That is the whole difference, and it is why this
/// is one file rather than a widget and a sheet in two of the feature's pages.
///
/// Rendered as the design's cost lines, in the order that adds up: the inspector's
/// share, then the platform's, then the total they make. All three, because a buyer
/// deciding whether to accept an offer is deciding about the fee inside it, and a
/// single number would ask them to take the platform's cut on trust. Written once
/// because both sides need exactly this breakdown — the buyer deciding whether to
/// accept an offer, and the inspector checking what they asked for — and because the
/// two would otherwise each re-derive the total by adding the other two, which is the
/// one piece of arithmetic this product has decided no client may do.
class _Split extends StatelessWidget {
  const _Split({required this.net, required this.fee, required this.total});

  final double net;
  final double fee;
  final double total;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CostLine(
          label: l10n.budgetInspectorShare,
          value: CostEstimate.format(net),
        ),
        CostLine(
          label: l10n.budgetPlatformFee,
          value: CostEstimate.format(fee),
        ),
        const DashedDivider(indent: AppSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(l10n.budgetYourTotal, style: AppText.title(13)),
            ),
            Text(
              CostEstimate.format(total),
              style: AppText.title(13, color: AppColors.green),
            ),
          ],
        ),
      ],
    );
  }
}

/// What the buyer ends up paying, on their own request.
///
/// Replaces the create form's cost box on the detail page. Where that one is a *quote*
/// — the numbers that were on screen when they filed — this one is a *fact*: the
/// figures `enforce_bidding` wrote when the job was claimed or the last offer was
/// accepted. A buyer reading "you pay" is reading a figure the platform will charge,
/// not one recomputed from a setting that may since have moved.
class OfferOutcomeCard extends StatelessWidget {
  const OfferOutcomeCard({required this.request, super.key});

  final InspectionRequest request;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final BidSummary summary = BidSummary.of(request);

    return CostBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.budgetBreakdownTitle,
            style: AppText.title(13, color: AppColors.greenDeep),
          ),
          const SizedBox(height: AppSpacing.sm),
          CostLine(
            label: l10n.createCostCentre,
            value: summary.centreFee == null
                ? l10n.invoiceCentrePending
                : CostEstimate.format(summary.centreFee!),
          ),
          // `defaultNet` rather than `inspectorNet ?? 0`: before the job is claimed
          // there is no snapshot, and the buyer's budget *is* what their share would
          // be. Showing zero would say the platform is handing the job away.
          CostLine(
            label: l10n.budgetInspectorShare,
            value: CostEstimate.format(
              summary.inspectorNet ?? summary.defaultNet,
            ),
          ),
          CostLine(
            label: l10n.budgetPlatformFee,
            value: CostEstimate.format(summary.platformFee),
          ),
          const DashedDivider(color: AppColors.successBorder),
          Row(
            children: <Widget>[
              Expanded(
                flex: 2,
                // "You pay", not the create form's "Current estimated total:". This
                // card is a fact — the figures a trigger wrote — and calling a settled
                // total an estimate invites the buyer to wonder what it might become.
                child: Text(
                  l10n.budgetYourTotal,
                  style: AppText.title(12, color: AppColors.greenDeep),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                flex: 3,
                child: Text(
                  _total(context, summary),
                  textAlign: TextAlign.end,
                  style: AppText.title(12, color: AppColors.green),
                ),
              ),
            ],
          ),
          // A spread rather than an `if`: the extension returns null for
          // [BidStatus.none], and a null in a spread would leave an empty string
          // where a card edge used to be.
          ...<Widget>[
            if (summary.status.localizedName(context)
                case final String name) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(name, style: AppText.secondary(11)),
            ],
          ],
          const SizedBox(height: AppSpacing.sm),
          // Why the two lines above are the buyer's to read rather than to choose.
          // A buyer who sees a figure and a cut taken from it is owed an explanation
          // of which part is which, and the centre line is the third thing they
          // cannot influence at all — so all three are named in one sentence.
          Text(l10n.costEstimateNotice, style: AppText.secondary(11)),
        ],
      ),
    );
  }

  /// What the buyer owes in total, and whether that number is final.
  ///
  /// Two shapes, because two different facts are known. With a centre chosen, the fee
  /// is a number and the total is a sum — the same arithmetic `ClientDashboardPage`'s
  /// invoice does, which is why it is stated here rather than approximated. Without
  /// one, the centre line above reads "still to come", so a bare total would understate
  /// what the buyer owes; the create form's "… + centre fee" shape says the number is
  /// incomplete instead of implying it is the whole bill.
  static String _total(BuildContext context, BidSummary summary) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double? centreFee = summary.centreFee;

    if (centreFee == null) {
      return l10n.createCostTotalValue(CostEstimate.format(summary.buyerTotal));
    }
    return CostEstimate.format(summary.buyerTotal + centreFee);
  }
}

/// The inspector's earnings card, with the button that opens the counter-offer sheet.
///
/// Placed on the job page rather than the market card because quoting is a decision
/// about a job, and an inspector scrolling a list of ten jobs is not deciding about
/// any of them. It shows the earnings the claim already earned them — which is the
/// budget minus the fee, or the agreed net — and offers the one thing an inspector can
/// do about a number they think is too low.
class InspectorEarningsCard extends ConsumerWidget {
  const InspectorEarningsCard({required this.request, super.key});

  final InspectionRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionBid>> offers = ref.watch(
      inspectionOffersProvider(request.id),
    );
    final bool busy = ref.watch(bidControllerProvider).isLoading;

    // The same summary the buyer's page builds, from the same columns.
    final BidSummary summary = BidSummary.of(
      request,
      offers: offers.value ?? const <InspectionBid>[],
    );

    // Before a claim there is no snapshot and nothing to show — and no offer is
    // possible then either, so the whole card is absent rather than half-rendered.
    final double? net = summary.inspectorNet;
    if (net == null) return const SizedBox.shrink();

    final InspectionBid? open = summary.openOffer;
    // One open offer at a time, and while one stands the button is hidden rather
    // than disabled: `seal_bid` supersedes a pending offer silently, and a button
    // that would quietly replace it is worse than no button. The buyer refusing and
    // the inspector re-offering is the only path back to a second round.
    final bool canCounter = request.status.isClaimed && open == null;
    final String? declinedReason = switch (summary.status) {
      BidStatus.declined => request.counterNote,
      _ => null,
    };

    return DesignCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.bidYourEarnings, style: AppText.title(13)),
          const SizedBox(height: AppSpacing.sm),
          CostLine(
            label: l10n.bidOfferNet,
            value: CostEstimate.format(net),
            valueColor: AppColors.green,
          ),
          // Stated while nothing has been negotiated. An inspector looking at a net
          // has no way to tell whether the platform chose it or the buyer did, and
          // "the same as the buyer's budget" is the difference between an opening
          // position and a settled one.
          if (summary.status == BidStatus.none)
            Text(l10n.bidSameAsBudget, style: AppText.secondary(11)),
          // The total the buyer pays, next to the net the inspector keeps. Gated on
          // `agreed_total` rather than on the fee: there is no figure to print until
          // the claim writes it, and a total beside an earned net with no basis is
          // the arithmetic the reader would otherwise have to do.
          if (summary.agreedTotal != null) ...<Widget>[
            const DashedDivider(indent: AppSpacing.sm),
            CostLine(
              label: l10n.bidOfferTotal,
              value: CostEstimate.format(summary.buyerTotal),
            ),
          ],
          if (open != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            // The round number is stated because a second offer is a different deal
            // from the first, and the buyer is about to be asked to choose between them.
            Text(l10n.bidRound(open.round), style: AppText.secondary(11)),
            Text(l10n.bidStatusPending, style: AppText.secondary(11)),
          ],
          if (declinedReason case final String reason
              when reason.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.bidPreviousReason(reason), style: AppText.secondary(11)),
          ],
          if (canCounter) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => showCounterOfferSheet(
                      context: context,
                      ref: ref,
                      request: request,
                    ),
              child: Text(l10n.bidMakeOffer),
            ),
          ],
        ],
      ),
    );
  }
}

/// The inspector's counter-offer form.
///
/// A sheet rather than a pushed page: it is four lines over a page the inspector is
/// already reading, and the number they are editing is on the sheet. Pushing would
/// hide the job the offer is about.
Future<void> showCounterOfferSheet({
  required BuildContext context,
  required WidgetRef ref,
  required InspectionRequest request,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => Padding(
      // `viewInsets` rather than a fixed height: the sheet has a text field and a
      // soft keyboard covering two thirds of it is a sheet with no send button.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: _CounterOfferForm(request: request),
    ),
  );
}

class _CounterOfferForm extends ConsumerStatefulWidget {
  const _CounterOfferForm({required this.request});

  final InspectionRequest request;

  @override
  ConsumerState<_CounterOfferForm> createState() => _CounterOfferFormState();
}

class _CounterOfferFormState extends ConsumerState<_CounterOfferForm> {
  late final TextEditingController _net = TextEditingController(
    text: _plain(widget.request.inspectorNet ?? widget.request.price),
  );
  late final TextEditingController _note = TextEditingController();

  /// The form the amount is validated through.
  ///
  /// Present because [DesignTextField]'s `validator` only runs inside a [Form], and
  /// without one a typed `0` would enable the send button and be offered to the
  /// database — which would refuse it, but as a server error on a field the buyer
  /// typed wrong. The sheet is not inside the page's own form: a bottom sheet is a
  /// separate route, and a `Form` does not cross one.
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _net.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The buyer's budget expressed as the inspector's own share.
  ///
  /// Prefilled rather than left blank, and pre-filled with the *right* number: the net
  /// the claim already earned. An inspector who opens this sheet and closes it has
  /// then made no change, which is the common case by a long way — a blank field
  /// would make that no-change require retyping a figure.
  static String _plain(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  double? get _netValue => double.tryParse(_net.text.trim());

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool busy = ref.watch(bidControllerProvider).isLoading;
    final double? net = _netValue;
    final double? fee = widget.request.platformFee;

    // The fee is a snapshot on the row, so the total below is the real one rather than
    // an estimate from a setting that may have moved. Before a claim there is no
    // snapshot — and no offer is possible then either, so the line is simply absent
    // rather than computed from a current setting that is not the one that will apply.
    final double? total = net == null || fee == null ? null : net + fee;

    return SafeArea(
      child: Form(
        key: _form,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.bidOfferTitle, style: AppText.title(16)),
              const SizedBox(height: AppSpacing.md),
              FieldLabel(l10n.fieldNetBid),
              DesignTextField(
                controller: _net,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                // Western digits throughout the app, and a number laid out against an
                // RTL paragraph puts its own units at the wrong end.
                ltr: true,
                validator: (String? value) => _validate(value),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.xs),
              // Why the total under this field is larger than the number in it. An
              // inspector quoting a net who is not told that the buyer pays the fee on
              // top will read the higher total as an error, and will be tempted to
              // subtract the fee again to "fix" it.
              Text(l10n.fieldNetBidHint, style: AppText.secondary(11)),
              if (total != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                CostLine(
                  label: l10n.bidOfferTotal,
                  value: CostEstimate.format(total),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FieldLabel(l10n.fieldBidNote),
              DesignTextField(
                controller: _note,
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                // Enabled on a parsable number and validated on the way out, so the
                // button is not greyed out on a half-typed figure — a permanently
                // disabled button with no explanation is the worse of the two failure
                // modes.
                onPressed: net == null || busy ? null : () => _submit(net),
                child: Text(l10n.actionSubmitOffer),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _validate(String? raw) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double? amount = double.tryParse((raw ?? '').trim());
    if (amount == null || amount <= 0) {
      return l10n.bidErrorAmountRange('${CostEstimate.maxBudget.round()}');
    }
    return null;
  }

  Future<void> _submit(double net) async {
    final AppLocalizations l10n = AppLocalizations.of(context);

    // The range check, before the write. Refused here rather than by the database's
    // own constraint because a constraint surfaces as a failed request with a
    // sentence the inspector cannot act on, and the field they mistyped is right
    // above the button they just pressed.
    if (!(_form.currentState?.validate() ?? false)) return;

    try {
      await ref
          .read(bidControllerProvider.notifier)
          .submit(
            inspectionId: widget.request.id,
            netAmount: net,
            note: _note.text,
          );
    } on InspectionFailure catch (failure) {
      // `mounted` rather than `context.mounted` because both uses below are a State's
      // own — its `context` and its `ScaffoldMessenger` — and this State owns them.
      if (!mounted) return;
      _show(localizedOfferFailure(context, failure.reason));
      return;
    } on Object {
      if (!mounted) return;
      _show(l10n.bidErrorSubmit);
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
