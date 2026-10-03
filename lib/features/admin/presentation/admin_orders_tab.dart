import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cities/presentation/city_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inspections/application/inspection_controller.dart';
import '../../inspections/data/inspection_repository.dart';
import '../../inspections/domain/inspection_draft.dart';
import '../../inspections/domain/inspection_request.dart';
import '../../inspections/domain/order_filter.dart';
import '../../inspections/presentation/widgets/design_widgets.dart';
import '../../inspections/presentation/widgets/request_widgets.dart';
import '../application/admin_controller.dart';
import '../domain/order_summary.dart';

/// Every order on the platform, filtered, with the status breakdown below them.
///
/// The breakdown is rendered from `admin_order_summary` — grouped in the database —
/// and the rows from a second read. Two reads rather than one because the breakdown
/// must survive the filters: an admin who filters to one status still wants to see
/// where the rest of the platform is, and a count computed from the filtered page
/// would answer a different question from the one they asked.
///
/// The row cap belongs to the repository, and [_TruncationNotice] compares against it
/// so the two cannot disagree. A monitor that silently shows the most recent 200 of
/// four thousand orders and lets an admin conclude that 200 exist is worse than none.
class AdminOrdersTab extends ConsumerWidget {
  const AdminOrdersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<InspectionRequest>> orders = ref.watch(
      adminOrdersProvider,
    );
    final List<OrderSummary> summary =
        ref.watch(orderSummaryProvider).value ?? const <OrderSummary>[];

    return Column(
      children: <Widget>[
        const _FilterBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(adminOrdersProvider);
              ref.invalidate(orderSummaryProvider);
            },
            child: switch (orders) {
              AsyncData<List<InspectionRequest>>(
                value: final List<InspectionRequest> rows,
              )
                  when rows.isEmpty =>
                ListView(
                  children: <Widget>[DesignEmpty(title: l10n.adminOrdersEmpty)],
                ),
              AsyncData<List<InspectionRequest>>(
                value: final List<InspectionRequest> rows,
              ) =>
                _OrderList(rows: rows, summary: summary),
              AsyncError<List<InspectionRequest>>() => ListView(
                children: <Widget>[
                  DesignRetry(
                    message: l10n.errorGeneric,
                    actionLabel: l10n.actionRetry,
                    onRetry: () => ref.invalidate(adminOrdersProvider),
                  ),
                ],
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ],
    );
  }
}

/// The rows, with the truncation notice first and the breakdown last.
///
/// The breakdown goes *under* the list rather than above it. It describes the whole
/// platform, and a count describing four thousand orders sitting above a list of the
/// forty that matched reads as a heading for what follows.
class _OrderList extends StatelessWidget {
  const _OrderList({required this.rows, required this.summary});

  final List<InspectionRequest> rows;
  final List<OrderSummary> summary;

  @override
  Widget build(BuildContext context) {
    // One slot each, whether or not they render anything: keeping the offsets fixed
    // means an index cannot address the wrong row when the notice hides itself.
    const int noticeSlots = 1;
    final int summarySlots = summary.isEmpty ? 0 : 1;

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: rows.length + noticeSlots + summarySlots,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) return _TruncationNotice(count: rows.length);
        if (index == rows.length + noticeSlots) {
          return _SummaryBlock(rows: summary);
        }
        return _OrderCard(order: rows[index - noticeSlots]);
      },
    );
  }
}

/// The filter controls, always on screen rather than behind a button.
///
/// An admin monitoring a platform switches between "who is stuck" and "what is big"
/// every few seconds; a hidden filter sheet turns each switch into a two-tap detour,
/// and the count of active filters is easier to trust when the controls that set it
/// are the ones on screen.
class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar();

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<_FilterBar> {
  late final TextEditingController _search = TextEditingController();
  late final TextEditingController _minValue = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    _minValue.dispose();
    super.dispose();
  }

  void _set(OrderFilter next) =>
      ref.read(adminOrdersFilterProvider.notifier).set(next);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final OrderFilter filter = ref.watch(adminOrdersFilterProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        children: <Widget>[
          TextField(
            controller: _search,
            // Submitted rather than changed: the term goes to the database, and one
            // query per character is one query too many on a connection the admin is
            // already waiting on.
            textInputAction: TextInputAction.search,
            textAlign: TextAlign.start,
            onSubmitted: (String value) => _set(filter.copyWith(search: value)),
            decoration: InputDecoration(
              labelText: l10n.adminFilterSearch,
              prefixIcon: const Icon(Icons.search, size: 20),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: SelectField(
                  label: l10n.adminFilterStatus,
                  value: _statusLabel(context, filter.status),
                  muted: filter.status == null,
                  onTap: () => _pickStatus(context, filter),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SelectField(
                  label: l10n.adminFilterCity,
                  value: filter.city ?? '',
                  muted: filter.city == null || filter.city!.isEmpty,
                  onTap: () => _pickCity(context, filter),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _minValue,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.left,
                  onSubmitted: (String value) {
                    final double? parsed = double.tryParse(value.trim());
                    _set(
                      filter.copyWith(
                        minValue: parsed,
                        clearMinValue: parsed == null,
                      ),
                    );
                  },
                  decoration: InputDecoration(labelText: l10n.adminFilterMinValue),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SelectField(
                  label: l10n.adminFilterFrom,
                  value: _dayLabel(context, filter.from),
                  muted: filter.from == null,
                  onTap: () => _pickBound(context, filter, upper: false),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SelectField(
                  label: l10n.adminFilterTo,
                  value: _dayLabel(context, filter.to),
                  muted: filter.to == null,
                  onTap: () => _pickBound(context, filter, upper: true),
                ),
              ),
            ],
          ),
          if (filter.isActive) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                Text(
                  l10n.adminFilterCount(filter.activeCount),
                  style: AppText.secondary(12),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    _search.clear();
                    _minValue.clear();
                    _set(OrderFilter.none);
                  },
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: Text(l10n.adminFilterClear),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickStatus(BuildContext context, OrderFilter filter) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final InspectionStatus? chosen = await showModalBottomSheet<InspectionStatus?>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            for (final InspectionStatus status in InspectionStatus.values)
              ListTile(
                title: Text(_statusLabel(context, status)),
                trailing: filter.status == status
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(status),
              ),
            // The sheet's own "no status" row.
            //
            // Without it, the only way to clear this one field is to reopen the sheet
            // and dismiss it — and a dismissal pops with `null`, the same value a
            // cancelled sheet returns. The field would be stuck on with no way out
            // but "clear everything and start again".
            ListTile(
              title: Text(l10n.adminFilterClear),
              onTap: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    );
    if (!mounted || chosen == null) return;
    _set(filter.copyWith(status: chosen));
  }

  Future<void> _pickCity(BuildContext context, OrderFilter filter) async {
    // The sheet returns the Arabic name from `cities` — the exact string the job
    // board compares against — so this filter is an equality match on the same value
    // the request was filed with, not a like against a free-text field. Dismissing
    // the sheet changes nothing; the "clear" row at the foot of the bar is the way to
    // unset this one.
    final String? picked = await showCitySheet(context, selected: filter.city);
    if (!mounted || picked == null) return;
    _set(filter.copyWith(city: picked));
  }

  /// Picks one end of the date range.
  ///
  /// One picker per bound rather than a single "choose a range" flow, because the
  /// two bounds are independent in [OrderFilter] and an admin monitoring a
  /// platform almost always wants one of them: "everything since Tuesday" and
  /// "everything before Friday" are the two real questions, and a two-step dialog
  /// makes the second one wait for the first.
  ///
  /// [upper] picks the `to` bound. The lower bound of its picker is the `from` that
  /// is already set, so a range can only ever run forwards — an `from` after a `to`
  /// is a filter that matches nothing, which reads as "no orders" rather than as a
  /// mistake.
  Future<void> _pickBound(
    BuildContext context,
    OrderFilter filter, {
    required bool upper,
  }) async {
    final DateTime now = DateTime.now();
    final DateTime earliest = DateTime(now.year - 5);
    final DateTime floor = upper ? filter.from ?? earliest : earliest;

    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: upper
          ? filter.to ?? now
          : filter.from ?? now,
      firstDate: floor,
      lastDate: now,
    );

    // `context.mounted` rather than this State's own flag: the check that matters is
    // whether the context still has somewhere to put the result, and checking
    // `mounted` would let this build pass and still write a filter onto a State the
    // user has already scrolled away from.
    if (!context.mounted) return;

    // A dismissal clears this one bound rather than leaving it as it was. Two ends
    // that clear independently, because an open-ended range is the common one, and a
    // picker the admin reopened and dismissed was a filter they meant to remove.
    if (day == null) {
      _set(
        upper
            ? filter.copyWith(clearTo: true)
            : filter.copyWith(clearFrom: true),
      );
      return;
    }

    _set(
      upper
          ? filter.copyWith(to: OrderFilter.endOfDay(day))
          : filter.copyWith(from: OrderFilter.startOfDay(day)),
    );
  }

  String _dayLabel(BuildContext context, DateTime? day) {
    if (day == null) return '';
    // The locale's own date format rather than the app's `SaudiFormat`: this is a
    // filter label, and `GlobalMaterialLocalizations` already renders dates for the
    // active locale in the direction they read in.
    return MaterialLocalizations.of(context).formatMediumDate(day.toLocal());
  }

  String _statusLabel(BuildContext context, InspectionStatus? status) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (status == null) return '';
    return switch (status) {
      InspectionStatus.pending => l10n.statusPending,
      InspectionStatus.accepted => l10n.statusAccepted,
      InspectionStatus.inProgress => l10n.statusInProgress,
      InspectionStatus.completed => l10n.statusCompleted,
      InspectionStatus.cancelled => l10n.statusCancelled,
    };
  }
}

/// The truncation notice, shown only when the result may be incomplete.
///
/// Reads the repository's own cap rather than a literal, because what it has to say
/// is "here are the most recent N" and a second copy of the number would eventually
/// disagree with the one that produced the list. At or below the cap the list *is*
/// the whole platform for this filter, so a notice there would invent a truncation
/// that did not happen.
class _TruncationNotice extends StatelessWidget {
  const _TruncationNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (count < InspectionRepository.maxMonitoredOrders) {
      return const SizedBox.shrink();
    }

    return NoticeBox(
      titleIcon: Icons.info_outline,
      child: Text(
        l10n.adminOrdersTruncated(count),
        style: AppText.secondary(13),
      ),
    );
  }
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({required this.rows});

  final List<OrderSummary> rows;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return DesignCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final OrderSummary row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      // The raw status name rather than a translated label. This
                      // block can hold a status this build has no copy for, and a
                      // blank cell beside its count would hide the one row an admin
                      // most needs to notice.
                      row.status,
                      style: AppText.secondary(12),
                    ),
                  ),
                  Text(
                    l10n.adminSummaryRow(
                      row.orders,
                      CostEstimate.format(row.value),
                    ),
                    style: AppText.title(13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One order, with the one action an admin can take on it.
class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});

  final InspectionRequest order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return DesignCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: LtrRegion(
                  child: Text(order.reference, style: AppText.title(15)),
                ),
              ),
              StatusChip(status: order.status, dense: true),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(order.carDescription, style: AppText.secondary(13)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(child: Text(order.city, style: AppText.secondary(12))),
              Text(
                CostEstimate.format(order.agreedTotal ?? order.price),
                style: AppText.title(13),
              ),
            ],
          ),
          // Only while the request is still open work: `enforce_inspection_transition`
          // refuses to cancel a finished inspection, so a button that was there would
          // be one that fails.
          if (order.status.isOpen) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _confirmCancel(context, ref),
                style: TextButton.styleFrom(foregroundColor: AppColors.live),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: Text(l10n.adminCancelOrder),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.adminCancelConfirm(order.reference)),
        content: Text(l10n.adminCancelNotify),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.adminCancelOrder),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(inspectionRequestControllerProvider.notifier).cancel(order.id);
      ref.invalidate(adminOrdersProvider);
      ref.invalidate(orderSummaryProvider);
    } on Object {
      // The panel's banner owns the message. The cancel button is still on screen
      // after a failure, so the failure is visible without a second report of it.
    }
  }
}