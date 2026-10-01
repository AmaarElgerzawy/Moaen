import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/saudi_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/auth_controller.dart';
import '../../auth/user_profile.dart';
import '../application/inspection_controller.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection_draft.dart';
import '../domain/inspection_report.dart';
import '../domain/inspection_request.dart';
import 'my_requests_page.dart';
import 'widgets/design_widgets.dart';

/// The buyer's four-tab shell: home, my requests, reports, account.
///
/// A shell rather than four routes, because the design draws one bottom bar with
/// four destinations and one screen around them, and a `GoRouter` route per tab
/// would put a back arrow on the wrong pages and drop the bar on every push. The
/// tabs keep their own state through [IndexedStack]: a buyer who checks a request
/// number and switches back should find the list where they left it, not refetch
/// it.
///
/// Tab 0 is the design's Screen 1. The other three are destinations the design's
/// bar names but does not draw, so they are built from the same design system
/// rather than left as Material defaults — see [BuyerReportsTab],
/// [BuyerInspectionsTab] and [BuyerAccountTab].
class ClientDashboardPage extends ConsumerStatefulWidget {
  const ClientDashboardPage({super.key});

  @override
  ConsumerState<ClientDashboardPage> createState() => _ClientDashboardPageState();
}

class _ClientDashboardPageState extends ConsumerState<ClientDashboardPage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          BuyerHomeTab(),
          MyRequestsBody(),
          BuyerReportsTab(),
          BuyerAccountTab(),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onTap: (int value) => setState(() => _index = value),
        // The design's bar is an `.ltr` container: `الرئيسية` sits at the
        // physical left, not at the physical right where the Arabic reading order
        // would put it.
        ltr: true,
        items: <BottomNavItem>[
          BottomNavItem(l10n.navHome),
          BottomNavItem(l10n.navMyRequestsTab),
          BottomNavItem(l10n.navReports),
          BottomNavItem(l10n.navAccount),
        ],
      ),
    );
  }
}

/// Screen 1: the buyer's home.
///
/// The design's `.sc` is an LTR container, so the greeting row, the pill and the
/// step circles all sit on the physical left even though every word in them is
/// Arabic. [LtrRegion] is applied once, here, rather than per widget, so the whole
/// screen agrees with itself.
///
/// The content is real: the greeting from the profile, the card from
/// [dashboardRequestProvider], the invoice from the request's own booking, and the
/// approval button from the row that write goes to.
class BuyerHomeTab extends ConsumerWidget {
  const BuyerHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final UserProfile? profile = ref.watch(authControllerProvider).value;
    final AsyncValue<InspectionRequest?> active = ref.watch(
      dashboardRequestProvider,
    );

    final String name = profile?.fullName ?? '';

    return RefreshIndicator(
      // Pull-to-refresh matters more than usual here: status advances on the
      // inspector's phone and not on a push, so a buyer who left the app open has
      // no other way to learn that anything moved.
      onRefresh: () async {
        ref.invalidate(dashboardRequestProvider);
        ref.invalidate(myRequestsProvider);
        await ref.read(dashboardRequestProvider.future);
      },
      child: CustomScrollView(
        // Always scrollable, so the gesture works on the loading and empty
        // branches too. Without it a buyer with no requests cannot pull to
        // refresh, and pulling is how they would look for one that had arrived.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(child: _HomeHeader(name: name)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.inset,
              AppSpacing.inset,
              AppSpacing.inset,
              AppSpacing.xxl,
            ),
            sliver: SliverToBoxAdapter(
              child: active.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: CircularProgressIndicator(),
                  ),
                ),
                // A failed read and "no active request" lead to the same primary
                // action, so they share one empty state — but the failure keeps
                // its retry, because only one of the two is worth trying again.
                error: (_, _) => DesignEmpty(
                  title: l10n.dashboardNoActiveTitle,
                  body: l10n.dashboardNoActiveBody,
                  action: DesignRetry(
                    message: l10n.tabLoadError,
                    actionLabel: l10n.actionRetry,
                    onRetry: () => ref.invalidate(dashboardRequestProvider),
                  ),
                ),
                data: (InspectionRequest? request) => request == null
                    ? DesignEmpty(
                        title: l10n.dashboardNoActiveTitle,
                        body: l10n.dashboardNoActiveBody,
                        action: const _NewRequestButton(),
                      )
                    : _ActiveRequestCard(
                        request: request,
                        requesterName: request.clientName,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark header: the greeting row, then the green call to action.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return LtrRegion(
      child: DarkHeader(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.inset,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                InitialAvatar(
                  name: name,
                  // The design's greeting circle is 56dp with a 24sp initial, not
                  // the 32dp timeline circle.
                  diameter: 56,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        AppLocalizations.of(context).buyerGreeting,
                        style: AppText.secondary(
                          12,
                          color: AppColors.onDarkSoft,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // The design shows the given name alone. A first word
                        // rather than a substring, because `عبد الله` is one
                        // given name and cutting it in half would name someone
                        // who does not exist.
                        givenName(name),
                        style: AppText.onDark(22),
                      ),
                    ],
                  ),
                ),
                // The design's bare rounded square, with no glyph. Left inert:
                // see [HeaderSquare] on why a control nobody can press is a lie
                // about what the app does.
                const HeaderSquare(),
              ],
            ),
            const SizedBox(height: AppSpacing.inset),
            const _NewInspectionBanner(),
          ],
        ),
      ),
    );
  }

  /// Everything before the first space, or the whole name if it is one word.
  ///
  /// Empty for an unset profile, where the design's own text is a placeholder:
  /// the header must not print an empty line where a name belongs.
  static String givenName(String fullName) {
    final String trimmed = fullName.trim();
    if (trimmed.isEmpty) return '—';
    final int space = trimmed.indexOf(' ');
    return space == -1 ? trimmed : trimmed.substring(0, space);
  }
}

/// The green gradient card: the one place on this screen a buyer starts a new
/// inspection.
///
/// `.row` in the reference, which is `justify-content: space-between` — so the
/// text column and the chip are pushed to opposite ends. A `Row` with an
/// `Expanded` text column and an intrinsic chip reproduces that exactly, and the
/// text column has to flex: a `Row` hands its non-flex children unbounded
/// main-axis width, and this sentence would then overflow instead of wrapping
/// inside the 150dp the design caps it at.
class _NewInspectionBanner extends StatelessWidget {
  const _NewInspectionBanner();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.greenGradient,
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.buyerNewInspectionTitle,
                  style: AppText.onDark(18),
                ),
                const SizedBox(height: AppSpacing.xs),
                // The design caps this line at 150dp and lets it wrap to three
                // lines inside that. The cap is reproduced rather than dropped
                // because it is what keeps the chip from being pushed off the
                // card on a narrow phone.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    l10n.buyerNewInspectionBody,
                    style: AppText.secondary(
                      12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const _BookNowChip(),
        ],
      ),
    );
  }
}

/// The white chip inside the green banner: `اطلب +` over `الآن`.
///
/// The design's `+` is the app's own mark, not a Material icon, and it is on its
/// own line above the word — reproduced with an explicit two-line string rather
/// than with an icon and a label side by side, which would be a different shape.
class _BookNowChip extends StatelessWidget {
  const _BookNowChip();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => context.pushNamed('createRequest'),
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.inset,
            vertical: AppSpacing.row,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          child: Text(
            l10n.buyerNewInspectionAction,
            textAlign: TextAlign.center,
            style: AppText.title(15, color: AppColors.green).copyWith(
              height: 1.3,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// The empty state's standing button, so the header and the empty state reach the
/// create form through one widget rather than two.
class _NewRequestButton extends StatelessWidget {
  const _NewRequestButton();

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: () => context.pushNamed('createRequest'),
      child: Text(AppLocalizations.of(context).dashboardNewRequest),
    );
  }
}

/// The active request: where it is, what it costs, and the approval button.
class _ActiveRequestCard extends ConsumerWidget {
  const _ActiveRequestCard({required this.request, required this.requesterName});

  final InspectionRequest request;

  /// The buyer's name as filed on the request, shown in the timeline. Null for a
  /// request filed before migration 0009 froze the column, and the timeline then
  /// says the inspector is not yet named rather than inventing one.
  final String? requesterName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Object? writeError = ref.watch(
      inspectionRequestControllerProvider,
    ).error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.buyerActiveHeading(request.reference),
          style: AppText.title(15),
        ),
        const SizedBox(height: AppSpacing.md),
        DesignCard(
          onTap: () => context.pushNamed('requestDetail', pathParameters: {
            'id': request.id,
          }),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                // The design's `.row` is `align-items: flex-start` here, so the
                // city line sits under the car name rather than being centred
                // against a two-line pill.
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          request.carDescription,
                          style: AppText.title(16),
                        ),
                        Text(
                          l10n.buyerOrderCity(request.city),
                          style: AppText.secondary(12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppPill(label: statusPill(l10n, request), fontSize: 11),
                ],
              ),
              const DashedDivider(indent: AppSpacing.md),
              // A cancelled request has no timeline at all. Four grey circles
              // with numbers in them read as a queue the work is sitting in, and
              // the request is not in a queue — it was withdrawn. The divider
              // goes with it, so the card does not open with a rule and nothing
              // under it.
              if (request.status != InspectionStatus.cancelled) ...<Widget>[
                StepTimeline(
                  steps: _steps(context, request, requesterName),
                  reachedCount: _reachedCount(request),
                  ltr: true,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (request.status == InspectionStatus.cancelled)
                Text(
                  l10n.buyerCancelledBody,
                  style: AppText.secondary(12),
                ),
              if (request.hasBooking) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _AppointmentNotice(request: request),
              ],
              const SizedBox(height: AppSpacing.md),
              _Invoice(request: request),
              if (writeError != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _errorText(l10n, writeError),
                  style: AppText.secondary(12, color: AppColors.live),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The pill beside the car.
  ///
  /// Chosen from the request's own state rather than from the status alone,
  /// because "booked" is a claim about a centre *and* a time, which is a
  /// different fact from `accepted`: an inspector can accept a job today and
  /// choose the centre tomorrow, and the buyer should be able to tell the
  /// difference.
  ///
  /// `cancelled` is checked first and short-circuits every other branch. Left to
  /// fall through it would read "no inspector assigned yet", which is both wrong
  /// — the request is over rather than waiting — and quietly reassuring, which is
  /// the worse of the two. The design has no drawing for a cancelled request, so
  /// the pill borrows the one word the request list already uses for it.
  static String statusPill(AppLocalizations l10n, InspectionRequest request) {
    if (request.status == InspectionStatus.cancelled) {
      return l10n.statusCancelled;
    }
    if (request.status == InspectionStatus.completed) {
      return l10n.buyerPillReportReady;
    }
    if (request.hasBooking) return l10n.buyerPillBooked;
    if (request.status == InspectionStatus.pending) {
      return l10n.buyerPillAwaiting;
    }
    return l10n.buyerNoInspector;
  }

  /// The four steps the design draws, filled in from the request.
  ///
  /// The subtitles are conditional because the design's copy names a party and a
  /// place that a request at an earlier stage does not have: there is no centre
  /// to name before one is chosen, and the design's centre line names a *city*,
  /// not the centre. Printing a placeholder instead would tell the buyer
  /// something about their own request that is not true.
  static List<TimelineStep> _steps(
    BuildContext context,
    InspectionRequest request,
    String? requesterName,
  ) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final SaudiFormat format = SaudiFormat(
      Localizations.localeOf(context).toString(),
    );

    final String? centre = request.inspectionCenterName;
    final DateTime? when = request.appointmentAt;

    return <TimelineStep>[
      TimelineStep(
        title: l10n.stepAcceptedTitle,
        subtitle: request.inspectorId == null
            ? l10n.buyerNoInspector
            : requesterName == null
            ? l10n.buyerNoInspector
            : l10n.stepAcceptedSub(requesterName),
      ),
      TimelineStep(
        title: l10n.stepCoordinationTitle,
        subtitle: centre == null
            ? l10n.stepCoordinationPending
            : l10n.stepCoordinationSub(request.city),
      ),
      TimelineStep(
        title: l10n.stepAppointmentTitle,
        subtitle: when == null || centre == null
            ? l10n.stepAppointmentPending
            : l10n.stepAppointmentSub(
                format.weekday(when),
                format.time(when),
                centre,
              ),
        glyph: '📍',
      ),
      TimelineStep(
        title: l10n.stepInspectionTitle,
        subtitle: l10n.stepInspectionSub,
      ),
    ];
  }

  /// How many steps are *done*, 0..4.
  ///
  /// Read from the request's own columns rather than from a counter, because the
  /// two facts the design paints as done — a centre chosen and an appointment
  /// made — are both observable here, while `status` is only a proxy for them. A
  /// request at `accepted` with a booked centre has genuinely done the second
  /// step even though the status column has not caught up.
  ///
  /// A cancelled request is zero whatever else is true: the steps describe a
  /// transaction that is no longer happening.
  static int _reachedCount(InspectionRequest request) => switch (request.status) {
    InspectionStatus.pending => 0,
    InspectionStatus.accepted => request.hasBooking ? 2 : 1,
    InspectionStatus.inProgress => 3,
    InspectionStatus.completed => 4,
    InspectionStatus.cancelled => 0,
  };

  /// The write failure, in the buyer's own words.
  ///
  /// [InspectionFailure] carries a sentence written for a person; anything else
  /// is a bug in this build rather than a condition the buyer caused, and saying
  /// "please try again" about a bug is a lie about what retrying will do.
  static String _errorText(AppLocalizations l10n, Object error) =>
      error is InspectionFailure ? error.message : l10n.tabLoadError;
}

/// The design's yellow notice: the bell at the physical left, then the centre, the
/// day and the time on their own lines.
///
/// The reference writes them as five separate lines with the centre, the day and
/// the time in bold, which is a real hierarchy and not a paragraph: the buyer is
/// meant to be able to find the time without reading the rest. The bold is
/// reproduced as a heavier weight in the box's own brown.
class _AppointmentNotice extends StatelessWidget {
  const _AppointmentNotice({required this.request});

  final InspectionRequest request;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateTime? when = request.appointmentAt;
    final String? centre = request.inspectionCenterName;
    if (when == null || centre == null) return const SizedBox.shrink();

    final SaudiFormat format = SaudiFormat(
      Localizations.localeOf(context).toString(),
    );

    return NoticeBox(
      title: l10n.buyerNoticeTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.buyerNoticeWillInspect, style: _body),
          Text(l10n.buyerNoticeCentre(centre, request.city), style: _strong),
          Text(l10n.buyerNoticeDay, style: _body),
          Text(
            l10n.buyerNoticeWhen(
              format.weekday(when),
              format.timeLong(when),
            ),
            style: _strong,
          ),
          Text(l10n.buyerNoticeSent, style: _body),
        ],
      ),
    );
  }

  static const TextStyle _body = TextStyle(
    fontSize: 13,
    height: 1.7,
    color: AppColors.alertOn,
  );

  static const TextStyle _strong = TextStyle(
    fontSize: 13,
    height: 1.7,
    fontWeight: FontWeight.w700,
    color: AppColors.alertOn,
  );
}

/// The design's invoice box: three cost lines, the total, and the approval button.
///
/// Not a variant of the create screen's [CostBox] even though the two share a
/// shape, because they say different things. The create screen's light green is
/// "roughly this, and nothing is charged yet"; this one names the centre and asks
/// the buyer to agree to a figure. Sharing one widget would make that difference a
/// boolean, and the two boxes also differ in bullet, background and type size.
class _Invoice extends ConsumerWidget {
  const _Invoice({required this.request});

  final InspectionRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<void> busy = ref.watch(
      inspectionRequestControllerProvider,
    );
    final bool approved = request.clientApprovedAt != null;
    final double? centreFee = request.centerFee;

    // With a centre named, the estimate is a quote and the total includes it.
    // Without one the centre line says so rather than showing a zero, which would
    // read as "free".
    final double total =
        (centreFee ?? 0) +
        CostEstimate.defaultInspectorFee +
        CostEstimate.defaultPlatformFee;

    return InvoiceBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(l10n.invoiceTitle, style: AppText.title(13)),
              ),
              Text(
                l10n.invoiceTransparency,
                style: AppText.title(11, color: AppColors.green),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          CostLine(
            label: centreFee == null
                ? l10n.invoiceCentreFee
                : l10n.invoiceCentreFeeNamed(
                    request.inspectionCenterName ?? '',
                  ),
            value: centreFee == null
                ? l10n.invoiceCentrePending
                : CostEstimate.format(centreFee),
            // The pending line is a sentence, not a figure, so it needs the whole
            // row; giving it the figure's share would wrap it into three lines.
            valueSize: 11,
          ),
          CostLine(
            label: l10n.invoiceInspectorFeeInvoice,
            value: CostEstimate.format(CostEstimate.defaultInspectorFee),
          ),
          CostLine(
            label: l10n.invoicePlatformFeeInvoice,
            value: CostEstimate.format(CostEstimate.defaultPlatformFee),
            emphasise: true,
          ),
          const DashedDivider(indent: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.invoiceTotalLabel,
                  style: AppText.title(13),
                ),
              ),
              Text(
                CostEstimate.format(total),
                style: AppText.title(22, color: AppColors.green),
              ),
            ],
          ),
          if (approved)
            _ApprovedLine(message: l10n.invoiceApproved)
          else if (request.hasBooking)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: FilledButton(
                onPressed: busy.isLoading ? null : () => _approve(ref),
                child: Text(l10n.invoiceApprove),
              ),
            ),
        ],
      ),
    );
  }

  /// Records the approval and lets the notifier invalidate the dashboard, so the
  /// success state comes from the database's answer rather than from a local flag.
  ///
  /// A failure is left to the card's own red line rather than a snackbar: the
  /// button is inside the card, and a message that appears at the bottom of the
  /// screen would be read as belonging to something else.
  Future<void> _approve(WidgetRef ref) async {
    await ref
        .read(inspectionRequestControllerProvider.notifier)
        .approveInvoice(request.id);
  }
}

/// The line that replaces the approval button once the buyer has approved.
class _ApprovedLine extends StatelessWidget {
  const _ApprovedLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Text(
        message,
        style: AppText.title(12, color: AppColors.greenDeep),
      ),
    );
  }
}

/// Tab 3: the buyer's issued reports.
///
/// One card per certified report, opening the A4 document. Only certified
/// reports are listed — [myReportsProvider] filters on `certified_at` — because a
/// half-written report is not a report, and offering one would tell a buyer that
/// findings exist before they do.
class BuyerReportsTab extends ConsumerWidget {
  const BuyerReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionReport>> reports = ref.watch(
      myReportsProvider,
    );

    return Column(
      children: <Widget>[
        ShellHeader(title: l10n.navReports),
        Expanded(
          child: reports.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: DesignRetry(
                message: l10n.tabLoadError,
                actionLabel: l10n.actionRetry,
                onRetry: () => ref.invalidate(myReportsProvider),
              ),
            ),
            data: (List<InspectionReport> rows) {
              if (rows.isEmpty) {
                return Center(
                  child: DesignEmpty(
                    title: l10n.reportsEmpty,
                    body: l10n.reportsEmptyBody,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.inset),
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (BuildContext context, int index) {
                  final InspectionReport report = rows[index];
                  return DesignCard(
                    onTap: () => context.pushNamed('report', pathParameters: {
                      'id': report.inspectionId,
                    }),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            l10n.reportsTitle,
                            style: AppText.title(14),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        AppPill(
                          label: l10n.reportCertified,
                          fontSize: 11,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Tab 4: the buyer's account.
///
/// Sign-out lives here and not on the home header: the design's header square is
/// empty, and a control the design has no room for belongs on the tab whose whole
/// subject is the account.
class BuyerAccountTab extends ConsumerWidget {
  const BuyerAccountTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final UserProfile? profile = ref.watch(authControllerProvider).value;

    return Column(
      children: <Widget>[
        ShellHeader(title: l10n.accountTitle),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.inset),
            children: <Widget>[
              DesignCard(
                child: Row(
                  children: <Widget>[
                    InitialAvatar(name: profile?.fullName ?? ''),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            profile?.fullName ?? '—',
                            style: AppText.title(15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profile?.email ?? '',
                            style: AppText.secondary(12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DesignCard(
                child: Column(
                  children: <Widget>[
                    AccountRow(
                      label: l10n.accountRoleLabel,
                      value: _roleLabel(l10n, profile),
                    ),
                    const DashedDivider(indent: AppSpacing.sm),
                    AccountRow(
                      label: l10n.accountCityLabel,
                      value: profile?.locationCity ?? '—',
                    ),
                    const DashedDivider(indent: AppSpacing.sm),
                    AccountRow(
                      label: l10n.accountPhoneLabel,
                      value: (profile?.phone ?? '').isEmpty
                          ? '—'
                          : profile!.phone,
                    ),
                    const DashedDivider(indent: AppSpacing.sm),
                    AccountRow(
                      label: l10n.accountRating,
                      value: profile == null || profile.rating == 0
                          ? l10n.detailNoRatingsYet
                          : profile.rating.toStringAsFixed(2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                style: AppTheme.blackButton,
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
                child: Text(l10n.actionSignOut),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The role's name, in words.
  ///
  /// Not derived from [UserRole.name]: that is the database's English spelling
  /// and this is the one screen where the user's account type is the subject.
  static String _roleLabel(AppLocalizations l10n, UserProfile? profile) =>
      switch (profile?.role) {
        UserRole.inspector => l10n.roleInspector,
        UserRole.admin => l10n.roleAdmin,
        _ => l10n.roleClient,
      };
}
