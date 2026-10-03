import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pricing/commission.dart';
import '../../../core/pricing/commission_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../inspections/domain/inspection_draft.dart';
import '../../inspections/presentation/widgets/design_widgets.dart';
import '../application/admin_controller.dart';

/// The platform commission.
///
/// Two controls — a type and a number — because the commission is one of two things
/// and the difference is not cosmetic: 49 is a flat 49 SAR under [CommissionType.fixed]
/// and a 49% cut under [CommissionType.percent]. A single "amount" field with a type
/// toggle beside it would let an admin type a percentage while the type still reads
/// "fixed", and the number would be taken literally.
///
/// The value the admin sees is what the database will use for *new* offers. Offers
/// already sealed keep the fee they were created with, so changing this never
/// retroactively rewrites a price somebody agreed to. The hint says so, because an
/// admin who has just watched a live negotiation would otherwise expect it to.
class AdminSettingsTab extends ConsumerWidget {
  const AdminSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<Commission> current = ref.watch(commissionProvider);

    return switch (current) {
      AsyncData<Commission>(value: final Commission commission) =>
        _CommissionForm(commission: commission),
      AsyncError<Commission>() => DesignRetry(
        message: l10n.errorGeneric,
        actionLabel: l10n.actionRetry,
        onRetry: () => ref.invalidate(commissionProvider),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _CommissionForm extends ConsumerStatefulWidget {
  const _CommissionForm({required this.commission});

  final Commission commission;

  @override
  ConsumerState<_CommissionForm> createState() => _CommissionFormState();
}

class _CommissionFormState extends ConsumerState<_CommissionForm> {
  late CommissionType _type = widget.commission.type;
  late final TextEditingController _value = TextEditingController(
    text: _text(widget.commission.value),
  );

  /// Set by a successful save and cleared by any edit.
  ///
  /// Local rather than derived from the provider, so the confirmation describes the
  /// save that just happened instead of reappearing after every unrelated rebuild.
  /// Deriving it from the provider's value would be wrong in the other direction too:
  /// the first build after `invalidate` would show "saved" before the refetch landed.
  bool _saved = false;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  static String _text(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  void _set(CommissionType type, double? value) {
    setState(() {
      _type = type;
      _value.text = value == null ? _value.text : _text(value);
      _saved = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double? parsed = double.tryParse(_value.text.trim().trim());

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        DesignCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.adminCommissionTitle, style: AppText.title(16)),
              const SizedBox(height: AppSpacing.md),
              SegmentedChoice(
                options: <String>[
                  l10n.adminCommissionFixed,
                  l10n.adminCommissionPercent,
                ],
                selectedIndex: _type == CommissionType.fixed ? 0 : 1,
                onChanged: (int index) =>
                    _set(index == 0 ? CommissionType.fixed : CommissionType.percent, null),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                // A number, always left-to-right, even in an Arabic panel: the digits
                // are Western throughout the app and a right-aligned number reads as a
                // different number when the field is mirrored.
                textAlign: TextAlign.left,
                onChanged: (_) => setState(() => _saved = false),
                decoration: InputDecoration(
                  labelText: l10n.adminCommissionValue,
                  suffixText: _type == CommissionType.percent
                      ? '%'
                      : CostEstimate.currencySuffix,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.adminCommissionHint, style: AppText.secondary(13)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _WorkedExample(type: _type, value: parsed),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          // Disabled on an unparseable value or a save already in flight. Both are
          // states the button can see; neither is worth an error message.
          onPressed: parsed == null || ref.watch(adminControllerProvider).isLoading
              ? null
              : () => _save(parsed),
          child: Text(l10n.actionSave),
        ),
        if (_saved) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          NoticeBox(
            child: Text(l10n.adminCommissionSaved),
          ),
        ],
      ],
    );
  }

  Future<void> _save(double value) async {
    try {
      await ref
          .read(adminControllerProvider.notifier)
          .setCommission(Commission(type: _type, value: value));
      if (!mounted) return;
      setState(() => _saved = true);
    } on Object {
      // The panel's banner owns the message; see the same catch in the other tabs.
    }
  }
}

/// The commission restated as the two figures a buyer and an inspector would see.
///
/// Shown before the save rather than after, because the thing an admin is actually
/// deciding is "what does this do to a 500 SAR job", and a percentage alone does not
/// answer that. It is arithmetic on the number in the field and nothing more — no
/// request is priced here, and the database remains the only thing that computes a
/// real fee.
class _WorkedExample extends StatelessWidget {
  const _WorkedExample({required this.type, required this.value});

  final CommissionType type;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double? amount = value;
    if (amount == null) return const SizedBox.shrink();

    final Commission commission = Commission(type: type, value: amount);
    // The design's own worked figure. Any would do, but a round one makes the two
    // numbers legible at a glance, which is the whole purpose of the box.
    const double example = 500;

    return NoticeBox(
      titleIcon: Icons.calculate_outlined,
      // The bare number, not `CostEstimate.format`: the sentence already says "SAR",
      // and a formatted amount in it would read "On a 500 ر.س SAR request".
      title: l10n.adminCommissionExample('${example.round()}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ExampleLine(
            label: l10n.adminCommissionFee,
            value: CostEstimate.format(commission.feeFor(example)),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ExampleLine(
            label: l10n.adminCommissionInspector,
            value: CostEstimate.format(commission.netFor(example)),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ExampleLine(
            label: l10n.adminCommissionTotal,
            value: CostEstimate.format(example),
          ),
        ],
      ),
    );
  }
}

class _ExampleLine extends StatelessWidget {
  const _ExampleLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: AppText.secondary(13))),
        Text(value, style: AppText.title(13)),
      ],
    );
  }
}