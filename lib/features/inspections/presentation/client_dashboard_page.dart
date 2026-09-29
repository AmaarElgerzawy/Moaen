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
            // Dark greeting banner: the slate hero from the design, with the
            // buyer's initial avatar so the header reads as *their* space.
            _GreetingBanner(name: auth.value?.fullName ?? ''),
            const SizedBox(height: AppSpacing.lg),
            _HeroBanner(
              title: l10n.heroTitle,
              body: l10n.heroBody,
              action: l10n.heroAction,
              onRequest: () => context.pushNamed('createRequest'),
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

/// The dark greeting banner over the dashboard.
class _GreetingBanner extends StatelessWidget {
  const _GreetingBanner({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              initial,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              l10n.dashboardGreeting(name),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The emerald action banner: the one place a buyer starts a new inspection.
class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.title,
    required this.body,
    required this.action,
    required this.onRequest,
  });

  final String title;
  final String body;
  final String action;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.emerald,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                Icons.directions_car_outlined,
                color: Colors.white.withValues(alpha: 0.9),
                size: 34,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            // The white-on-emerald inversion is the design's hero CTA: on the
            // dark-green banner the button is white with the brand green text.
            child: FilledButton(
              onPressed: onRequest,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.emerald,
              ),
              child: Text(action),
            ),
          ),
        ],
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
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    // Status-aware, because the card now shows the most recent
                    // request whatever its status. A completed inspection
                    // labelled "your active request" is telling the buyer their
                    // finished report is still in progress.
                    switch (request.status) {
                      InspectionStatus.completed => l10n.dashboardReportReadyTitle,
                      InspectionStatus.cancelled => l10n.dashboardCancelledTitle,
                      _ => l10n.dashboardActiveTitle,
                    },
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StatusChip(status: request.status, dense: true),
              ],
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
            _ProgressTrack(status: request.status),
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            _CostBreakdown(price: request.price),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
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

/// The four states a request passes through, as a vertical timeline.
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
        for (int i = 0; i < labels.length; i++)
          _StepRow(
            label: labels[i],
            reached: step >= 0 && i <= step,
            number: i + 1,
            // The connector hangs below every circle but the last.
            showConnector: i < labels.length - 1,
            connectorReached: step >= 0 && i < step,
          ),
      ],
    );
  }
}

/// One rung of the vertical timeline: a status circle with the connector line
/// beneath it, and the label beside it.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.reached,
    required this.number,
    required this.showConnector,
    required this.connectorReached,
  });

  final String label;
  final bool reached;
  final int number;
  final bool showConnector;
  final bool connectorReached;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    // A `Row` hands its non-flex children *unbounded* main-axis constraints, so
    // the label column must be the flexing side (Expanded) and the circle
    // column stays at its intrinsic width — the same rule that governs every
    // icon-plus-text row on these screens under RTL.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Column(
          children: <Widget>[
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: reached ? colors.primary : Colors.transparent,
                border: Border.all(
                  color: reached ? colors.primary : colors.outlineVariant,
                  width: 2,
                ),
                shape: BoxShape.circle,
              ),
              child: reached
                  ? Icon(Icons.check, size: 14, color: colors.onPrimary)
                  : Center(
                      child: Text(
                        '$number',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
            ),
            if (showConnector) ...<Widget>[
              const SizedBox(height: 4),
              Container(
                width: 2,
                height: 24,
                color: connectorReached
                    ? colors.primary
                    : colors.outlineVariant,
              ),
            ],
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: reached ? colors.onSurface : colors.onSurfaceVariant,
                fontWeight: reached ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
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

    return Container(
      // The same light-green estimate surface as the create form's box, so the
      // number a buyer approved and the number on the tracker both live on the
      // same visual surface.
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.successSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
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
      ),
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
                ? text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.emerald,
                  )
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
