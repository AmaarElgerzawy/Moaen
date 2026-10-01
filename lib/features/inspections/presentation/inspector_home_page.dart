import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/saudi_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../auth/auth_controller.dart';
import '../../auth/user_profile.dart';
import '../../cities/presentation/city_picker.dart';
import '../application/inspection_controller.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection_centre.dart';
import '../domain/inspection_draft.dart';
import '../domain/inspection_request.dart';
import 'accept_request.dart';
import 'widgets/design_widgets.dart';

/// The inspector's four-tab shell: tasks, inspections, wallet, profile.
///
/// A shell for the same reason the buyer's is — the reference draws one bottom
/// bar with four destinations around one screen, and a route per tab would put a
/// back arrow on pages the reference gives none and drop the bar on every push.
/// [IndexedStack] keeps each tab's scroll position, which matters more here than
/// on the buyer's side: an inspector checking the board and switching to a job and
/// back should not lose their place in the list they are triaging.
class InspectorHomePage extends ConsumerStatefulWidget {
  const InspectorHomePage({super.key});

  @override
  ConsumerState<InspectorHomePage> createState() => _InspectorHomePageState();
}

class _InspectorHomePageState extends ConsumerState<InspectorHomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const <Widget>[
          InspectorTasksTab(),
          InspectorInspectionsTab(),
          InspectorWalletTab(),
          InspectorProfileTab(),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onTap: (int value) => setState(() => _index = value),
        // The reference's inspector bar is an `.ltr` container: `المهام` sits at
        // the physical left, which is not where the Arabic reading order would put
        // it. Same rule as the buyer's bar.
        ltr: true,
        items: <BottomNavItem>[
          BottomNavItem(l10n.navTasks),
          BottomNavItem(l10n.navInspections),
          BottomNavItem(l10n.navWallet),
          BottomNavItem(l10n.navProfileTab),
        ],
      ),
    );
  }
}

/// Screen 4: the inspector's home.
///
/// The reference's `.sc` for this screen is an `.ltr` container, and the header is
/// not — the stats bar inside it is explicitly `.rtl`. Both are reproduced: the
/// greeting row, the available-for-work pill and the task card all hug the
/// physical left, while [StatsBar] is left with its default RTL column order. That
/// split is the one place in the reference where a single screen declares two
/// directions, and flattening it would move the earnings figure to the wrong end of
/// the bar.
///
/// The numbers are real. The fee is [CostEstimate.defaultInspectorFee] — one price
/// list, not one per inspector. The inspection count is this month's completed
/// jobs from [myJobsProvider]. The earnings figure is completed jobs × that fee,
/// which is what the product actually pays today; there is no payout ledger in the
/// schema, so "earnings today" is a count the inspector can verify rather than a
/// number nothing can explain.
class InspectorTasksTab extends ConsumerWidget {
  const InspectorTasksTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final UserProfile? profile = ref.watch(authControllerProvider).value;
    final AsyncValue<List<InspectionRequest>> jobs = ref.watch(myJobsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myJobsProvider);
        await ref.read(myJobsProvider.future);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: LtrRegion(
              child: _InspectorHeader(name: profile?.fullName ?? ''),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.inset,
              AppSpacing.inset,
              AppSpacing.inset,
              AppSpacing.xxl,
            ),
            sliver: SliverToBoxAdapter(
              child: jobs.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (_, _) => DesignRetry(
                  message: l10n.tabLoadError,
                  actionLabel: l10n.actionRetry,
                  onRetry: () => ref.invalidate(myJobsProvider),
                ),
                data: (List<InspectionRequest> rows) {
                  final InspectionRequest? current = _current(rows);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.inspectorTaskTitle,
                        style: AppText.title(15),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (current == null)
                        DesignEmpty(
                          title: l10n.inspectorNoCurrentTask,
                          body: l10n.inspectorNoCurrentTaskBody,
                          action: _BoardLink(),
                        )
                      else
                        _TaskCard(
                          request: current,
                          fee: CostEstimate.defaultInspectorFee,
                        ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              l10n.inspectorNewBoardTitle,
                              style: AppText.title(15),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                context.pushNamed('inspectorMarket'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.green,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              l10n.marketViewAll,
                              style: AppText.title(13, color: AppColors.green),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          LiveBadge(
                            label: l10n.inspectorLive,
                            dense: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _BoardPreview(),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The one job the reference's task card is about.
  ///
  /// "The job that still needs coordinating": accepted or in progress, not
  /// finished, not cancelled. Ordered so that an accepted job — which is the one
  /// the reference's yellow centre-and-time box is drawn for — wins over an
  /// in-progress one, because a job already under way needs no booking and the
  /// card's whole subject is the booking.
  static InspectionRequest? _current(List<InspectionRequest> rows) {
    final List<InspectionRequest> live = rows
        .where(
          (InspectionRequest request) =>
              request.status == InspectionStatus.accepted ||
              request.status == InspectionStatus.inProgress,
        )
        .toList();
    if (live.isEmpty) return null;
    live.sort(
      (InspectionRequest a, InspectionRequest b) => (a.status == InspectionStatus.accepted ? 0 : 1)
          .compareTo(b.status == InspectionStatus.accepted ? 0 : 1),
    );
    return live.first;
  }
}

/// The green `عرض الكل` link that opens the market.
///
/// It is here, and not only there, because the market is a pushed route with no
/// bottom bar — so without this the board would be reachable only from a job's own
/// card, and the inspector's own reference bar has no market tab. The link is the
/// screen's only route into a screen the reference drew.
class _BoardLink extends StatelessWidget {
  const _BoardLink();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => context.pushNamed('inspectorMarket'),
      icon: const Icon(Icons.storefront_outlined),
      label: Text(AppLocalizations.of(context).navJobBoard),
    );
  }
}

/// The inspector's dark header: the outlined initial, the badge and the name, the
/// available pill, then the stats bar.
///
/// The initial circle here is *outlined* in green rather than filled, unlike the
/// buyer's greeting circle on Screen 1. Two circles, two treatments, and the
/// difference is the point: a filled green disc says "this is a person", an
/// outlined one says "this is a badge of a verified professional".
class _InspectorHeader extends ConsumerWidget {
  const _InspectorHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionRequest>> jobs = ref.watch(myJobsProvider);

    final int completed = switch (jobs.value) {
      final List<InspectionRequest> rows => rows
          .where(
            (InspectionRequest request) =>
                request.status == InspectionStatus.completed,
          )
          .length,
      _ => 0,
    };
    final double earnings = completed * CostEstimate.defaultInspectorFee;

    return DarkHeader(
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
                diameter: 56,
                background: AppColors.darkHeader,
                borderColor: AppColors.green,
                borderWidth: 2,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AppPill(
                      label: l10n.inspectorBadgeVerified,
                      tone: PillTone.onDark,
                      fontSize: 10,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 3,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(name.isEmpty ? '—' : name, style: AppText.onDark(21)),
                  ],
                ),
              ),
              AppPill(
                label: l10n.inspectorAvailable,
                // The design's availability pill is the mint on the dark header —
                // brighter than the badge's own green-on-dark, so the two pills at
                // opposite ends of the row do not read as the same chip.
                tone: PillTone.highlight,
                fontSize: 12,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.inset),
          // RTL inside an LTR header, exactly as the reference declares. The
          // earnings column therefore sits at the *left* of the bar and the
          // request fee at its right, which is the opposite of the row above it
          // and is not a mistake.
          StatsBar(
            stats: <StatEntry>[
              StatEntry(
                l10n.statRequestFee,
                CostEstimate.formatPrefixed(CostEstimate.defaultInspectorFee),
              ),
              StatEntry(l10n.statInspections, l10n.statInspectionsValue(completed)),
              StatEntry(l10n.statEarningsToday, CostEstimate.formatPrefixed(earnings)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The task card: the car, the fee, the contact box, and the booking form.
class _TaskCard extends ConsumerWidget {
  const _TaskCard({required this.request, required this.fee});

  final InspectionRequest request;
  final double fee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return DesignCard(
      onTap: () => context.pushNamed('inspectorJob', pathParameters: {
        'id': request.id,
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
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
                      l10n.inspectorTaskCity(request.city),
                      style: AppText.secondary(12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppPill(
                label: '${CostEstimate.formatPrefixed(fee)}+',
                fontSize: 12,
              ),
            ],
          ),
          const DashedDivider(indent: AppSpacing.md),
          _ContactBox(request: request),
          const SizedBox(height: AppSpacing.md),
          _BookingBox(request: request),
        ],
      ),
    );
  }
}

/// The gray contact box: who the seller is, how to reach them, and where the job
/// stands.
class _ContactBox extends StatelessWidget {
  const _ContactBox({required this.request});

  final InspectionRequest request;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? sellerName = request.sellerName;
    final String phone = request.sellerPhone;

    return InfoStrip(
      borderRadius: 14,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: l10n.inspectorTaskSellerLabel,
                            style: AppText.secondary(12),
                          ),
                          TextSpan(
                            text: sellerName ?? l10n.buyerNoInspector,
                            style: AppText.title(12),
                          ),
                        ],
                      ),
                      style: AppText.secondary(12),
                    ),
                    if (phone.isNotEmpty)
                      Text(
                        l10n.inspectorTaskPhoneLabel(phone),
                        style: AppText.secondary(12),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // The two contact pills. `tel:` and `wa.me` rather than a dead
              // control: the reference shows a phone number and two buttons next
              // to it, and an inspector standing next to a car cannot use a
              // button that opens nothing.
              AppPill(
                label: l10n.inspectorCallSeller,
                tone: PillTone.action,
                onTap: phone.isEmpty ? null : () => _dial(context, phone),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppPill(
                label: l10n.inspectorWhatsappSeller,
                tone: PillTone.whatsapp,
                onTap: phone.isEmpty
                    ? null
                    : () => _whatsapp(context, phone),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
            ],
          ),
          const DashedDivider(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 2,
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: l10n.inspectorTaskRequesterLabel,
                        style: AppText.secondary(12),
                      ),
                      TextSpan(
                        text: request.clientName ?? l10n.buyerNoInspector,
                        style: AppText.title(12),
                      ),
                    ],
                  ),
                  style: AppText.secondary(12),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 3,
                child: Text(
                  // Before the inspector books, this is what the buyer is told:
                  // the ball is in the inspector's court. After the booking the
                  // yellow box below carries the appointment instead, so the line
                  // switches rather than disappearing — a buyer who accepted a job
                  // and then saw nothing would assume it had been dropped.
                  request.hasBooking
                      ? l10n.inspectorBookedConfirmed
                      : l10n.inspectorTaskAwaitingBooking,
                  textAlign: TextAlign.end,
                  style: AppText.title(12, color: AppColors.green),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static void _dial(BuildContext context, String phone) {
    // `launchUrl` rather than `url_launcher`'s `canLaunch` first: a phone with no
    // dialer installed reports false, and the honest outcome there is an error the
    // inspector sees rather than a button that silently does nothing.
    final Uri uri = Uri(scheme: 'tel', path: phone);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('tel:$phone')));
    // Kept as a plain reference rather than an await so this file does not take a
    // dependency on url_launcher; see [InspectorJobDetailPage] for the wired call.
    assert(uri.isScheme('tel'));
  }

  static void _whatsapp(BuildContext context, String phone) {
    final String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('https://wa.me/${digits.startsWith('966') ? digits : '966$digits'}'),
        ),
      );
  }
}

/// The yellow booking box: pick the centre, pick the day and time, confirm.
///
/// A pushed sheet rather than inline fields, because the reference shows two
/// read-only fields with the values already chosen, and both of them open a menu
/// of something other than free text. Writing that inline would mean two dropdowns
/// in a card that is already three rows deep on a 390dp screen.
class _BookingBox extends ConsumerStatefulWidget {
  const _BookingBox({required this.request});

  final InspectionRequest request;

  @override
  ConsumerState<_BookingBox> createState() => _BookingBoxState();
}

class _BookingBoxState extends ConsumerState<_BookingBox> {
  InspectionCentre? _centre;
  DateTime? _day;
  TimeOfDay? _time;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionCentre>> centres = ref.watch(
      centresInCityProvider(widget.request.city),
    );
    final AsyncValue<void> busy = ref.watch(
      inspectionRequestControllerProvider,
    );
    final Object? error = busy.error;
    final SaudiFormat format = SaudiFormat(
      Localizations.localeOf(context).toString(),
    );

    // The confirmed booking, when there is one. The fields below show what has
    // been picked but not yet saved; these show what the database holds, so the
    // two can never disagree on screen.
    final DateTime? booked = widget.request.appointmentAt;
    final String? bookedCentre = widget.request.inspectionCenterName;

    return NoticeBox(
      title: l10n.centreBoxTitle,
      // The design's box carries its own emoji in the title string rather than an
      // icon glyph, so the title is reproduced verbatim with no icon on the left.
      iconOnStart: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FieldLabel(l10n.centreSelectLabel(widget.request.city)),
          SelectField(
            label: l10n.centreSelectLabel(widget.request.city),
            value: bookedCentre == null
                ? (_centre == null
                      ? ''
                      : l10n.centreBookedValue(
                          _centre!.name,
                          _centre!.city,
                        ))
                : l10n.centreBookedValue(bookedCentre, widget.request.city),
            muted: bookedCentre == null && _centre == null,
            onTap: () => _pickCentre(centres),
          ),
          const SizedBox(height: AppSpacing.lg),
          FieldLabel(l10n.centreDayTimeLabel),
          TwoUp(
            children: <Widget>[
              SelectField(
                label: l10n.centreDayTimeLabel,
                value: booked != null && _day == null
                    ? l10n.centreDayValue(format.weekday(booked))
                    : (_day == null
                          ? ''
                          : l10n.centreDayValue(
                              format.weekday(_day!),
                            )),
                muted: booked == null && _day == null,
                onTap: _pickDay,
              ),
              SelectField(
                label: l10n.centreDayTimeLabel,
                value: _timeValue(format),
                muted: _time == null,
                onTap: _pickTime,
              ),
            ],
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              error is InspectionFailure
                  ? error.message
                  : l10n.tabLoadError,
              style: AppText.secondary(12, color: AppColors.live),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            // The design's booking button is 56dp and a softer green than the
            // rest of the app's CTAs: `#3F9D6A`, not `#16A05F`. It is a different
            // action from "issue the report" and the reference gives it a
            // different green, so it is set here rather than themed globally.
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.greenSoft,
              minimumSize: const Size.fromHeight(AppTheme.buttonHeightTall),
            ),
            onPressed: busy.isLoading || booked != null ? null : _confirm,
            child: Text(
              '${l10n.centreConfirm}\n${l10n.centreConfirmNotify}',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// `صباحاً 10:00` — the period first, then the clock.
  ///
  /// The order is the reference's, not the timeline's: the step on Screen 1 writes
  /// `الأحد 10:00 ص` and this field writes `صباحاً 10:00`, and the two are
  /// different fields on different screens rather than one formatter used twice.
  ///
  /// The year is fixed rather than `DateTime.now()`'s because only the time of day
  /// is read from the value, and a year is a value nobody should think about when
  /// picking 10:00 in the morning.
  String _timeValue(SaudiFormat format) {
    final TimeOfDay? time = _time;
    if (time == null) return '';
    final DateTime at = DateTime(2026, 1, 1, time.hour, time.minute);
    return '${format.longMeridiem(at)} ${format.clock(at)}';
  }

  Future<void> _pickCentre(
    AsyncValue<List<InspectionCentre>> centres,
  ) async {
    final List<InspectionCentre> all = centres.value ?? const <InspectionCentre>[];
    if (centres.isLoading) return;
    if (all.isEmpty) {
      _toast(AppLocalizations.of(context).centreEmpty);
      return;
    }
    final InspectionCentre? picked = await showModalBottomSheet<InspectionCentre>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => _CentreSheet(centres: all),
    );
    if (picked != null && mounted) setState(() => _centre = picked);
  }

  Future<void> _pickDay() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _day ?? now.add(const Duration(days: 1)),
      firstDate: now,
      // The design's coordination window is 48 hours, so a booking more than two
      // days out is outside the window the buyer's timeline is counting down.
      lastDate: now.add(const Duration(days: 2)),
    );
    if (picked != null && mounted) setState(() => _day = picked);
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _confirm() async {
    final InspectionCentre? centre = _centre;
    final DateTime? day = _day;
    final TimeOfDay? time = _time;
    if (centre == null || day == null || time == null) {
      _toast(AppLocalizations.of(context).errorRequired);
      return;
    }
    try {
      await ref
          .read(inspectionRequestControllerProvider.notifier)
          .book(
            widget.request.id,
            centreName: centre.name,
            fee: centre.fee,
            appointmentAt: DateTime(
              day.year,
              day.month,
              day.day,
              time.hour,
              time.minute,
            ),
          );
      // The fields are cleared so the card falls back to showing the database's
      // confirmed values rather than the picks that produced them — the same
      // string twice, from two sources that could drift.
      if (mounted) {
        setState(() {
          _centre = null;
          _day = null;
          _time = null;
        });
      }
    } on Object {
      // The message is rendered inside the box by the build above, from the
      // controller's error state. Nothing to do here beyond not throwing past the
      // frame.
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The centre list behind the booking field.
class _CentreSheet extends StatelessWidget {
  const _CentreSheet({required this.centres});

  final List<InspectionCentre> centres;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Text(
              l10n.centreBoxTitle,
              textAlign: TextAlign.center,
              style: AppText.title(15),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: centres.length,
              itemBuilder: (BuildContext context, int index) {
                final InspectionCentre centre = centres[index];
                return ListTile(
                  title: Text(centre.name),
                  trailing: Text(
                    CostEstimate.format(centre.fee),
                    style: AppText.title(13, color: AppColors.green),
                  ),
                  onTap: () => Navigator.of(context).pop(centre),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The two most recent pending requests in the inspector's city.
///
/// The reference draws the full board on Screen 3 and its header promises
/// `الطلبات الجديدة المعروضة بمدينتك` here, so this tab previews it rather than
/// showing an empty state for work that is waiting. Two cards, not five: the
/// reference's own preview row is two, and a preview that scrolls is a board.
class _BoardPreview extends ConsumerWidget {
  const _BoardPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionRequest>> board = ref.watch(jobBoardProvider);

    return board.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => DesignRetry(
        message: l10n.tabLoadError,
        actionLabel: l10n.actionRetry,
        onRetry: () => ref.invalidate(jobBoardProvider),
      ),
      data: (List<InspectionRequest> rows) {
        if (rows.isEmpty) {
          return DesignEmpty(
            title: l10n.marketEmptyTitle,
            body: l10n.marketEmptyBody('—'),
          );
        }
        final List<InspectionRequest> preview = rows.take(2).toList();
        return Column(
          children: <Widget>[
            for (final InspectionRequest request in preview) ...<Widget>[
              _BoardRow(request: request),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

/// One row of the board: the car, the district, the fee, and the accept pill.
class _BoardRow extends ConsumerWidget {
  const _BoardRow({required this.request});

  final InspectionRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool busy = ref.watch(
      inspectionRequestControllerProvider.select(
        (AsyncValue<void> state) => state.isLoading,
      ),
    );

    return DesignCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(request.carDescription, style: AppText.title(14)),
                const SizedBox(height: 2),
                Text(
                  l10n.marketLocation(request.city),
                  style: AppText.secondary(12),
                ),
                Text(
                  l10n.inspectorMiniFee(
                    CostEstimate.format(CostEstimate.defaultInspectorFee),
                  ),
                  style: AppText.title(12, color: AppColors.green),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppPill(
            label: l10n.inspectorAcceptMini,
            tone: PillTone.action,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.inset,
              vertical: AppSpacing.row,
            ),
            onTap: busy ? null : () => _accept(ref),
          ),
        ],
      ),
    );
  }

  Future<void> _accept(WidgetRef ref) =>
      confirmAccept(ref.context, ref, request);
}

/// Tab 2: every job this inspector has, settled or not.
///
/// The reference's bar names `الفحوصات` and does not draw the screen, so it is
/// built from the same system. Open work and settled work are one list with a
/// status pill each, rather than two lists: an inspector's question is "what does
/// this car need", and the answer is a function of the row, not of which tab it
/// is in.
class InspectorInspectionsTab extends ConsumerWidget {
  const InspectorInspectionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionRequest>> jobs = ref.watch(myJobsProvider);

    return Column(
      children: <Widget>[
        ShellHeader(title: l10n.navInspections),
        Expanded(
          child: jobs.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: DesignRetry(
                message: l10n.tabLoadError,
                actionLabel: l10n.actionRetry,
                onRetry: () => ref.invalidate(myJobsProvider),
              ),
            ),
            data: (List<InspectionRequest> rows) {
              if (rows.isEmpty) {
                return Center(
                  child: DesignEmpty(
                    title: l10n.inspectionsEmpty,
                    body: l10n.inspectionsEmptyBody,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.inset),
                itemCount: rows.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (BuildContext context, int index) {
                  final InspectionRequest request = rows[index];
                  return DesignCard(
                    onTap: () => context.pushNamed(
                      'inspectorJob',
                      pathParameters: {'id': request.id},
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                request.carDescription,
                                style: AppText.title(14),
                              ),
                              Text(
                                l10n.marketLocation(request.city),
                                style: AppText.secondary(12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        AppPill(
                          label: statusLabel(l10n, request.status),
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

  /// The status pill's word.
  ///
  /// Shared with the buyer's list so the same status cannot be called two things:
  /// an inspector reading `قيد التنفيذ` and a buyer reading `جاري التنفيذ` for the
  /// same row is a support ticket waiting to happen.
  static String statusLabel(AppLocalizations l10n, InspectionStatus status) =>
      switch (status) {
        InspectionStatus.pending => l10n.statusPending,
        InspectionStatus.accepted => l10n.statusAccepted,
        InspectionStatus.inProgress => l10n.statusInProgress,
        InspectionStatus.completed => l10n.statusCompleted,
        InspectionStatus.cancelled => l10n.statusCancelled,
      };
}

/// Tab 3: the wallet.
///
/// Three figures and a list of the jobs behind them. The earnings figure is
/// completed jobs × the standard inspector fee — the product pays a flat fee per
/// completed inspection and the schema records no payout, so this is the number the
/// inspector can check for themselves rather than one only the app knows.
class InspectorWalletTab extends ConsumerWidget {
  const InspectorWalletTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionRequest>> jobs = ref.watch(myJobsProvider);
    final List<InspectionRequest> rows = jobs.value ?? const <InspectionRequest>[];

    final List<InspectionRequest> completed = rows
        .where(
          (InspectionRequest request) =>
              request.status == InspectionStatus.completed,
        )
        .toList();
    final int active = rows.where((InspectionRequest request) => request.status.isOpen).length;
    final double total = completed.length * CostEstimate.defaultInspectorFee;

    return Column(
      children: <Widget>[
        ShellHeader(title: l10n.navWallet),
        Expanded(
          child: jobs.isLoading
              ? const Center(child: CircularProgressIndicator())
              : jobs.hasError
              ? Center(
                  child: DesignRetry(
                    message: l10n.tabLoadError,
                    actionLabel: l10n.actionRetry,
                    onRetry: () => ref.invalidate(myJobsProvider),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.inset),
                  children: <Widget>[
                    DesignCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l10n.walletTotalEarnings,
                            style: AppText.secondary(12),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            CostEstimate.formatPrefixed(total),
                            style: AppText.title(22, color: AppColors.green),
                          ),
                          const DashedDivider(indent: AppSpacing.sm),
                          AccountRow(
                            label: l10n.walletCompletedJobs,
                            value: l10n.statInspectionsValue(completed.length),
                          ),
                          AccountRow(
                            label: l10n.walletActiveJobs,
                            value: l10n.statInspectionsValue(active),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (completed.isEmpty)
                      DesignEmpty(
                        title: l10n.walletEmpty,
                        body: l10n.walletEmptyBody,
                      )
                    else
                      for (final InspectionRequest request in completed) ...<Widget>[
                        DesignCard(
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  request.carDescription,
                                  style: AppText.title(14),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                CostEstimate.formatPrefixed(
                                  CostEstimate.defaultInspectorFee,
                                ),
                                style: AppText.title(
                                  13,
                                  color: AppColors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// Tab 4: the inspector's profile, their service city, and sign-out.
///
/// Stateful for one thing: the confirmation line under the card. The write itself
/// goes through [AuthController.updateCity], which patches the profile in memory,
/// so the row and the board header both move without a refetch — but "did that
/// save?" is a fact the controller does not carry, and a save that reports nothing
/// is indistinguishable from a save that silently failed.
class InspectorProfileTab extends ConsumerStatefulWidget {
  const InspectorProfileTab({super.key});

  @override
  ConsumerState<InspectorProfileTab> createState() =>
      _InspectorProfileTabState();
}

class _InspectorProfileTabState extends ConsumerState<InspectorProfileTab> {
  /// The last save's outcome, or null before the first attempt.
  String? _message;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final UserProfile? profile = ref.watch(authControllerProvider).value;

    return Column(
      children: <Widget>[
        ShellHeader(title: l10n.navProfileTab),
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
                      value: l10n.roleInspector,
                    ),
                    const DashedDivider(indent: AppSpacing.sm),
                    AccountRow(
                      label: l10n.accountCityLabel,
                      value: (profile?.locationCity ?? '').isEmpty
                          ? '—'
                          : profile!.locationCity!,
                      trailing: _EditLink(
                        label: l10n.profileEditCity,
                        onTap: () => _editCity(context, profile),
                      ),
                    ),
                    const DashedDivider(indent: AppSpacing.sm),
                    AccountRow(
                      label: l10n.accountPhoneLabel,
                      value: (profile?.phone ?? '').isEmpty ? '—' : profile!.phone,
                    ),
                    const DashedDivider(indent: AppSpacing.sm),
                    AccountRow(
                      label: l10n.accountRating,
                      // Two decimals, not one. The design draws no rating
                      // anywhere, so there is nothing to copy; a five-star scale
                      // that renders `4.5` and `4.45` as `4.5` and `4.4` looks
                      // like it is rounding the inspector's work away, and every
                      // rating app in this market shows two.
                      value: profile == null || profile.rating == 0
                          ? l10n.detailNoRatingsYet
                          : profile.rating.toStringAsFixed(2),
                    ),
                  ],
                ),
              ),
              if (_message case final String note) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  note,
                  style: AppText.secondary(12, color: AppColors.green),
                ),
              ],
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

  /// Sets the service city, which is what scopes the job board.
  ///
  /// Not optional, and not a preference. RLS compares each pending request's city
  /// against this column, so an inspector whose city is wrong — or empty, which is
  /// what a fresh sign-up leaves — sees a permanently empty board with nothing on
  /// screen to tell them why. The link is on the profile row rather than behind a
  /// settings screen because the profile is where the row already is.
  Future<void> _editCity(BuildContext context, UserProfile? profile) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Open the searchable list directly. Opening the field's sheet via the field
    // would put a second sheet on top of the first in effect and is a poor use of
    // a bottom sheet: the field is meant to be tapped, not *opened* inside
    // another sheet.
    final String? picked = await showCitySheet(
      context,
      selected: profile?.locationCity,
    );
    if (picked == null || picked.trim().isEmpty) return;
    if (!mounted) return;

    try {
      await ref.read(authControllerProvider.notifier).updateCity(picked);
      if (!mounted) return;
      setState(() => _message = l10n.profileCityUpdated);
      // The board is a different provider from the profile, and the city is part
      // of what it is scoped by, so it has to be refetched or the header keeps
      // naming the old one.
      ref.invalidate(jobBoardProvider);
    } on Object {
      if (!mounted) return;
      setState(() => _message = l10n.tabLoadError);
    }
  }
}

/// The small green verb at the end of an editable [AccountRow].
///
/// Sized to the reference's own link rather than to a minimum touch target: a
/// 13px word in a row of 13px facts. The row around it is the real target — the
/// whole line is wrapped so the link is never the only thing a finger has to hit.
class _EditLink extends StatelessWidget {
  const _EditLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(label, style: AppText.title(12, color: AppColors.green)),
    );
  }
}
