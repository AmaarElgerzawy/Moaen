import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/auth_controller.dart';
import '../../auth/user_profile.dart';
import '../application/inspection_controller.dart';
import '../domain/inspection_draft.dart';
import '../domain/inspection_request.dart';
import 'widgets/request_widgets.dart';

/// The buyer's home screen.
///
/// Built around one question — *where is my inspection right now* — because that
/// is what a buyer opens the app to find out. The reference number leads because
/// it is the thing they need to read out to the seller or an inspector.
class ClientDashboardPage extends ConsumerWidget {
  const ClientDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<UserProfile?> auth = ref.watch(authControllerProvider);
    final AsyncValue<InspectionRequest?> active = ref.watch(dashboardRequestProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navDashboard),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.actionSignOut,
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        // Pull-to-refresh matters here more than usual: status advances on the
        // inspector's phone, not on a push, so a buyer who left the app open has
        // no other way to learn it moved.
        onRefresh: () async {
          ref.invalidate(dashboardRequestProvider);
          ref.invalidate(myRequestsProvider);
          await ref.read(dashboardRequestProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: <Widget>[
            Text(
              l10n.dashboardGreeting(auth.value?.fullName ?? ''),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            active.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: CircularProgressIndicator(),
                ),
              ),
              // Not an error screen: a failed fetch and "no active request" both
              // lead to the same primary action, so they share the empty state
              // with a retry rather than two near-identical screens.
              error: (_, _) => _NoActiveRequest(
                onRetry: () => ref.invalidate(dashboardRequestProvider),
              ),
              data: (InspectionRequest? request) => request == null
                  ? const _NoActiveRequest()
                  : _ActiveRequestCard(request: request),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: () => context.pushNamed('createRequest'),
              icon: const Icon(Icons.add),
              label: Text(l10n.dashboardNewRequest),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => context.pushNamed('myRequests'),
              icon: const Icon(Icons.list_alt_outlined),
              label: Text(l10n.dashboardViewRequests),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveRequestCard extends StatelessWidget {
  const _ActiveRequestCard({required this.request});

  final InspectionRequest request;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              // Status-aware, because the card now shows the most recent
              // request whatever its status. A completed inspection labelled
              // "your active request" is telling the buyer their finished
              // report is still in progress.
              switch (request.status) {
                InspectionStatus.completed => l10n.dashboardReportReadyTitle,
                InspectionStatus.cancelled => l10n.dashboardCancelledTitle,
                _ => l10n.dashboardActiveTitle,
              },
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              request.reference,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                // Tabular figures so the number does not jitter in width as it
                // changes.
                //
                // Deliberately NOT given `textDirection: TextDirection.ltr`.
                // `MN-1001` is a single LTR run, so the bidi algorithm already
                // renders it as `MN-1001` — prefix and digits in the right
                // order — inside an RTL paragraph. Forcing LTR would also flip
                // `TextAlign.start` to *left*, so the number would sit on the
                // wrong edge of an Arabic screen while still looking correct in
                // isolation. `test/features/inspections/rtl_layout_test.dart`
                // pins both halves of that.
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              request.carDescription,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            StatusChip(status: request.status),
            const SizedBox(height: AppSpacing.lg),
            _ProgressTrack(status: request.status),
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            _CostBreakdown(price: request.price),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => context.pushNamed(
                  'requestDetail',
                  pathParameters: <String, String>{'id': request.id},
                ),
                child: Text(l10n.actionViewDetails),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four states a request passes through, as a row of dots.
///
/// Driven by [InspectionRequest.status] rather than by anything the client
/// infers: the inspector's actions are what move the request, and the app
/// sometimes learns about them late. Deriving progress from local guesses is how
/// a tracker ends up lying to the buyer about who is actually doing the work.
class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.status});

  final InspectionStatus status;

  /// How far along the status has moved, 0..3, or -1 for cancelled.
  static int _stepFor(InspectionStatus status) => switch (status) {
    InspectionStatus.pending => 0,
    InspectionStatus.accepted => 1,
    InspectionStatus.inProgress => 2,
    // Cancelled is not a step forward. It gets its own treatment below.
    InspectionStatus.completed => 3,
    InspectionStatus.cancelled => -1,
  };

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int step = _stepFor(status);

    if (status == InspectionStatus.cancelled) {
      // A cancelled request has no progress to show. Drawing four unfilled dots
      // would imply the work is merely late, when it will never happen.
      return Row(
        children: <Widget>[
          Icon(
            Icons.cancel_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            l10n.statusCancelled,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      );
    }

    final List<String> labels = <String>[
      l10n.dashboardStepRequested,
      l10n.dashboardStepMatched,
      l10n.dashboardStepInspecting,
      l10n.dashboardStepReport,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.dashboardSteps,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        // Dots and labels are two rows, not one row of columns.
        //
        // A `Row` hands its non-flex children *unbounded* main-axis constraints,
        // so a `Column` holding a label takes the label's full intrinsic width —
        // which is wider than a quarter of the card, and overflows. The English
        // labels happened to fit; the Arabic ones are longer, and this is
        // exactly the class of defect that shows up in Arabic and not in English.
        //
        // Splitting the rows gives the labels a tight quarter-width each, so
        // `Text` wraps and ellipsises inside the slot it was given. The dots keep
        // their natural size and the connectors stay flexible.
        Row(
          children: <Widget>[
            for (int i = 0; i < labels.length; i++) ...<Widget>[
              if (i > 0) _Connector(reached: step >= i),
              _Dot(reached: step >= 0 && i <= step),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int i = 0; i < labels.length; i++)
              Expanded(
                child: _StepLabel(
                  label: labels[i],
                  reached: step >= 0 && i <= step,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The line between two dots.
///
/// Drawn on the trailing side of every dot except the last, so the track reads
/// in the ambient direction without any direction logic here: under RTL the `Row`
/// reverses and the line lands on the correct side of each dot on its own.
class _Connector extends StatelessWidget {
  const _Connector({required this.reached});

  final bool reached;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        color: reached
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

/// One step's dot.
class _Dot extends StatelessWidget {
  const _Dot({required this.reached});

  final bool reached;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color border = reached ? colors.primary : colors.outlineVariant;

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: reached ? colors.primary : Colors.transparent,
        border: Border.all(color: border, width: 2),
        shape: BoxShape.circle,
      ),
      child: reached ? Icon(Icons.check, size: 12, color: colors.onPrimary) : null,
    );
  }
}

/// One step's label, in its own quarter-width slot.
class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.label, required this.reached});

  final String label;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: reached ? colors.onSurface : colors.onSurfaceVariant,
        fontWeight: reached ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }
}

/// The cost breakdown.
///
/// Reads the buyer's stated budget, not a quote — see `CostEstimate` for why
/// there is no priced breakdown in the database. The total is labelled as an
/// estimate so the number is not mistaken for a charge that has already happened.
class _CostBreakdown extends StatelessWidget {
  const _CostBreakdown({required this.price});

  final double price;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Reconstructs the same split the create form showed, so the number a buyer
    // approved and the number they now see cannot disagree. A single source for
    // the split matters: two screens deriving it differently is how a buyer ends
    // up wondering what changed.
    final CostEstimate estimate = CostEstimate(
      inspectionFee: price,
      travelFee: 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.costTitle,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        _CostRow(label: l10n.costInspection, value: estimate.inspectionFee),
        _CostRow(
          label: l10n.costTravel,
          value: estimate.travelFee,
          freeWhenZero: true,
        ),
        const SizedBox(height: AppSpacing.xs),
        _CostRow(
          label: l10n.costTotal,
          value: estimate.total,
          emphasise: true,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.costEstimateNotice,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow({
    required this.label,
    required this.value,
    this.emphasise = false,
    this.freeWhenZero = false,
  });

  final String label;
  final double value;
  final bool emphasise;
  final bool freeWhenZero;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final String shown = freeWhenZero && value == 0
        ? l10n.costFree
        : CostEstimate.format(value);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: emphasise
                ? text.titleSmall
                : text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
          ),
          const Spacer(),
          Text(
            shown,
            style: emphasise
                ? text.titleSmall?.copyWith(fontWeight: FontWeight.w800)
                : text.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _NoActiveRequest extends StatelessWidget {
  const _NoActiveRequest({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: <Widget>[
            Icon(
              Icons.directions_car_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.dashboardNoActiveTitle,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.dashboardNoActiveBody,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              TextButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
            ],
          ],
        ),
      ),
    );
  }
}
