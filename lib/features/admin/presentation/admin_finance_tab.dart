import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inspections/domain/inspection_draft.dart';
import '../../inspections/presentation/widgets/design_widgets.dart';
import '../application/admin_controller.dart';
import '../domain/financial_overview.dart';

/// What the platform has taken.
///
/// Four figures and a count, and deliberately not a chart. The questions an admin
/// actually asks are "how much came in", "how much of it is ours", "how much are we
/// holding for somebody" and "how much did we give back" — four numbers whose
/// relationships matter. A pie of them would hide the one figure that is not the
/// platform's at all, which is the escrow.
///
/// Every figure is read from `admin_financial_overview`, which is `security_invoker`,
/// so this screen is behind the same policies as everything else and there is no
/// privileged read that could show an admin something RLS would refuse.
class AdminFinanceTab extends ConsumerWidget {
  const AdminFinanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<FinancialOverview> overview = ref.watch(financialsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(financialsProvider),
      child: switch (overview) {
        AsyncData<FinancialOverview>(value: final FinancialOverview data)
            when data.isEmpty =>
          ListView(
            children: <Widget>[DesignEmpty(title: l10n.adminFinanceEmpty)],
          ),
        AsyncData<FinancialOverview>(value: final FinancialOverview data) =>
          ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: <Widget>[
              _Revenue(data: data),
              const SizedBox(height: AppSpacing.md),
              _Line(
                label: l10n.adminCollected,
                value: CostEstimate.format(data.collectedVolume),
              ),
              _Line(
                label: l10n.adminEscrow,
                value: CostEstimate.format(data.heldInEscrow),
              ),
              _Line(
                label: l10n.adminRefunded,
                value: CostEstimate.format(data.refunded),
              ),
            ],
          ),
        AsyncError<FinancialOverview>() => ListView(
          children: <Widget>[
            DesignRetry(
              message: l10n.errorGeneric,
              actionLabel: l10n.actionRetry,
              onRetry: () => ref.invalidate(financialsProvider),
            ),
          ],
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// The platform's own revenue, as the design's hero figure, plus the share it is.
///
/// The take rate is rendered as a percentage rather than a decimal for the same
/// reason the rest of the app writes `49 ر.س` and not `49.00`: these are figures a
/// person reads, and the rounding is done once, here, rather than by whoever formats
/// the number next.
class _Revenue extends StatelessWidget {
  const _Revenue({required this.data});

  final FinancialOverview data;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double? takeRate = data.takeRate;

    return DesignCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.adminRevenue, style: AppText.secondary(13)),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              CostEstimate.format(data.platformRevenue),
              style: AppText.title(28),
            ),
          ),
          if (takeRate != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.adminTakeRate('${(takeRate * 100).toStringAsFixed(1)}%'),
              style: AppText.secondary(12),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.adminPaymentsCount(data.completedPayments),
            style: AppText.secondary(12),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DesignCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.inset,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: AppText.secondary(13))),
          Text(value, style: AppText.title(15)),
        ],
      ),
    );
  }
}