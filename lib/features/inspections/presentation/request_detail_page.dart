import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/inspection_controller.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection_request.dart';
import 'offer_widgets.dart';
import 'widgets/design_widgets.dart';

/// One request in full, with the cancel action.
///
/// A pushed screen the reference does not draw, so it is built from the design
/// system rather than left as Material: a `DesignCard` per group, the buyer's
/// own status pill, and the same dark header every other pushed screen opens
/// with. It also has no bottom bar, for the reason Screens 2, 3 and 5 have none —
/// a screen you reached by tapping something is a screen you go back from.
///
/// The cancel action lives here rather than on the card because cancelling is
/// not reversible and touches a real transaction. A buyer should have to have
/// arrived at the request they mean.
class RequestDetailPage extends ConsumerWidget {
  const RequestDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<void> action = ref.watch(
      inspectionRequestControllerProvider,
    );

    // Reading through the list provider rather than fetching by id: the detail
    // page is always reached from a list that already has the row, so this is a
    // cache hit, and a second network read could show a *different* status than
    // the row the buyer tapped.
    final AsyncValue<List<InspectionRequest>> requests = ref.watch(
      myRequestsProvider,
    );

    // Resolved once, above the header, because both the header and the body need
    // it and two independent lookups of the same id are two chances to disagree.
    // Null while loading and when the id is genuinely absent; the body says so
    // and the header simply shows no pill rather than guessing a status.
    final InspectionRequest? match = switch (requests.value) {
      final List<InspectionRequest> all => all
          .where((InspectionRequest r) => r.id == id)
          .firstOrNull,
      _ => null,
    };

    return Scaffold(
      body: Column(
        children: <Widget>[
          ShellHeader(
            title: l10n.actionViewDetails,
            // The reference number is the one identifier a buyer is given, and
            // the only one they are asked to read out to the centre. It is the
            // header's trailing pill rather than its title because the title is
            // the *kind* of screen, and a row of two numbers at the top of a
            // detail page is the layout the design uses for a row of one number
            // plus a pill.
            trailing: match == null ? null : StatusPill(status: match.status),
          ),
          Expanded(
            child: requests.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: DesignRetry(
                  message: l10n.tabLoadError,
                  actionLabel: l10n.actionRetry,
                  onRetry: () => ref.invalidate(myRequestsProvider),
                ),
              ),
              data: (List<InspectionRequest> _) {
                // A missing id is a navigation bug, not a data state: the row was
                // on screen a moment ago. Saying so plainly beats rendering an
                // empty screen that looks like a deleted request.
                if (match == null) {
                  return Center(
                    child: DesignEmpty(
                      title: l10n.errorGeneric,
                      body: l10n.actionViewDetails,
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.inset),
                  children: <Widget>[
                    Text(
                      match.reference,
                      style: AppText.title(20),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TitledCard(
                      title: l10n.cardCarTitle,
                      child: Column(
                        children: <Widget>[
                          AccountRow(
                            label: l10n.fieldCarMake,
                            value: match.carMake,
                          ),
                          const DashedDivider(indent: AppSpacing.sm),
                          AccountRow(
                            label: l10n.fieldCarModel,
                            value: match.carModel,
                          ),
                          const DashedDivider(indent: AppSpacing.sm),
                          AccountRow(
                            label: l10n.fieldCarYear,
                            value: '${match.carYear}',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TitledCard(
                      title: l10n.cardSellerTitle,
                      child: Column(
                        children: <Widget>[
                          AccountRow(
                            label: l10n.fieldSellerPhone,
                            value: match.sellerPhone,
                          ),
                          const DashedDivider(indent: AppSpacing.sm),
                          AccountRow(
                            label: l10n.fieldCity,
                            value: match.city,
                          ),
                          if (match.inspectionCenterName case final String name
                              when name.isNotEmpty) ...<Widget>[
                            const DashedDivider(indent: AppSpacing.sm),
                            AccountRow(
                              label: l10n.fieldInspectionCentre,
                              value: name,
                            ),
                          ],
                          if (match.appointmentAt case final DateTime at) ...<Widget>[
                            const DashedDivider(indent: AppSpacing.sm),
                            AccountRow(
                              label: l10n.buyerNoticeDay,
                              value: '${at.day}/${at.month}/${at.year}',
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (match.clientNotes case final String notes
                        when notes.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      TitledCard(
                        title: l10n.cardNotesTitle,
                        child: Text(notes, style: AppText.secondary(13)),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    // The counter-offer, when one is standing. Above the invoice
                    // rather than below it, because it is a *question* and the
                    // invoice below is the context for answering it — a buyer
                    // reading "you pay 249" needs to see the offer before they
                    // see what the offer changed.
                    BuyerOfferCard(request: match),
                    OfferOutcomeCard(request: match),
                    const SizedBox(height: AppSpacing.xl),
                    if (match.status.isOpen)
                      OutlinedButton(
                        // The reference has no destructive action of its own, so
                        // this takes the design's red — the same token the live
                        // indicator uses — as an outline rather than a fill. A
                        // filled red button on a screen the reference does not
                        // draw would be inventing an emphasis it never asked for.
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.live,
                          side: const BorderSide(color: AppColors.live),
                          minimumSize: const Size.fromHeight(
                            AppTheme.buttonHeight,
                          ),
                        ),
                        onPressed: action.isLoading
                            ? null
                            : () => _confirmCancel(context, ref, match),
                        child: Text(l10n.actionCancelRequest),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    InspectionRequest request,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.actionCancelConfirm),
        content: Text(l10n.actionCancelBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.actionCancelRequest),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // `l10n` was read before the dialog, so it is safe to use after the await.
    // Reading `AppLocalizations.of(context)` here would be a use of BuildContext
    // across an async gap.
    try {
      await ref
          .read(inspectionRequestControllerProvider.notifier)
          .cancel(request.id);
    } on InspectionFailure catch (failure) {
      if (!context.mounted) return;
      _showMessage(context, failure.message);
      return;
    } on Object {
      if (!context.mounted) return;
      _showMessage(context, l10n.errorGeneric);
      return;
    }

    if (!context.mounted) return;
    _showMessage(context, l10n.requestCancelled);
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The status pill, written once so two screens cannot word the same status
/// differently.
///
/// Deliberately tolerant of being given a request that is not on screen: the
/// header is built from the same list as the body, and the two reads happen in
/// the same frame, so the id either resolves in both or in neither. The `orElse`
/// above therefore cannot return a wrong status, only fail — and a failure here
/// would throw during a build, so the lookup is made safe instead.
class StatusPill extends StatelessWidget {
  const StatusPill({required this.status, super.key});

  final InspectionStatus status;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AppPill(
      label: switch (status) {
        InspectionStatus.pending => l10n.statusPending,
        InspectionStatus.accepted => l10n.statusAccepted,
        InspectionStatus.inProgress => l10n.statusInProgress,
        InspectionStatus.completed => l10n.statusCompleted,
        InspectionStatus.cancelled => l10n.statusCancelled,
      },
      fontSize: 11,
    );
  }
}
