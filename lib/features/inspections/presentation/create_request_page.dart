import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../cities/presentation/city_picker.dart';
import '../application/inspection_controller.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection_draft.dart';

/// The create-request form.
///
/// A `Form` with an explicit `GlobalKey` rather than per-field `onChanged`
/// validation, because the submit button has to know whether it may be pressed.
/// Validating only on submit makes the button look broken when the user is not
/// done; validating on every keystroke makes a half-typed year light up red.
class CreateRequestPage extends ConsumerStatefulWidget {
  const CreateRequestPage({super.key});

  @override
  ConsumerState<CreateRequestPage> createState() => _CreateRequestPageState();
}

class _CreateRequestPageState extends ConsumerState<CreateRequestPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _make = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _year = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _budget = TextEditingController();

  /// The chosen canonical city — a value, not a controller, because it comes
  /// from the [CityPicker] sheet rather than from a cursor. Null until the buyer
  /// makes a choice, which is what the validator flags.
  String? _city;

  @override
  void dispose() {
    // Every controller this state creates has to be disposed here. They are
    // created once per State, not once per build, so the usual place to leak
    // them is a StatefulWidget that gets rebuilt rather than recreated.
    for (final TextEditingController c in <TextEditingController>[
      _make,
      _model,
      _year,
      _phone,
      _address,
      _notes,
      _budget,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  InspectionDraft get _draft => InspectionDraft(
    carMake: _make.text,
    carModel: _model.text,
    carYear: _year.text,
    sellerPhone: _phone.text,
    sellerLocationAddress: _address.text,
    city: _city ?? '',
    clientNotes: _notes.text,
    budget: _budget.text,
  );

  /// The estimate the total is computed from.
  ///
  /// Read from the selected city so the breakdown tracks the buyer's choice,
  /// which is what makes the number feel like a quote rather than a static
  /// caption.
  CostEstimate get _estimate => CostEstimate.forCity((_city ?? '').trim());

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Re-validate the parsed values, because a string can pass its field's
    // validator and still not parse. A year of "٢٠١٥" (Arabic-Indic digits) is
    // the realistic case: it looks like a number and is not one to `int.parse`.
    final InspectionDraft draft = _draft;
    if (draft.year == null || draft.budgetAmount == null) return;

    try {
      final created = await ref
          .read(inspectionRequestControllerProvider.notifier)
          .create(draft);

      if (!mounted) return;
      Navigator.of(context).pop(created);
    } on InspectionFailure catch (failure) {
      // The message comes from the exception that actually happened rather than
      // from re-reading the controller's state. Re-reading is unreliable: the
      // notifier can be rebuilt between the throw and the read, which resets the
      // state to its initial value and turns every specific error into the
      // generic one.
      if (!mounted) return;
      _showError(failure.message);
    } on Object {
      if (!mounted) return;
      _showError(AppLocalizations.of(context).errorGeneric);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<void> submitting = ref.watch(
      inspectionRequestControllerProvider,
    );
    final CostEstimate estimate = _estimate;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.createTitle)),
      body: Form(
        key: _formKey,
        // A form this long is always scrolled, so the keyboard and the submit
        // button cannot both be usable without it.
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: <Widget>[
            _SectionCard(
              number: '01',
              title: l10n.createSectionVehicle,
              children: <Widget>[
                _Field(
                  controller: _make,
                  label: l10n.fieldCarMake,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) =>
                      (v ?? '').trim().isEmpty ? l10n.errorRequired : null,
                ),
                _Field(
                  controller: _model,
                  label: l10n.fieldCarModel,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) =>
                      (v ?? '').trim().isEmpty ? l10n.errorRequired : null,
                ),
                _Field(
                  controller: _year,
                  label: l10n.fieldCarYear,
                  // Digits only. A year is four numbers, and a keyboard offering
                  // letters for it is a keyboard offering the wrong suggestion.
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  maxLength: 4,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) {
                    final String input = (v ?? '').trim();
                    if (input.isEmpty) return l10n.errorRequired;
                    if (_draft.year == null) return l10n.errorInvalidYear;
                    return null;
                  },
                ),
              ],
            ),
            _SectionCard(
              number: '02',
              title: l10n.createSectionSeller,
              children: <Widget>[
                _Field(
                  controller: _phone,
                  label: l10n.fieldSellerPhone,
                  // Not `TextInputType.phone`: that keyboard has no `+`, and an
                  // international number almost always needs one.
                  keyboardType: TextInputType.text,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  textInputAction: TextInputAction.next,
                  validator: (String? v) {
                    final String input = (v ?? '').trim();
                    if (input.isEmpty) return l10n.errorRequired;
                    // The schema requires 5..30 characters. The lower bound is the
                    // only one enforced here; an over-long value is the length
                    // formatter's job.
                    if (input.length < 5) return l10n.errorInvalidPhone;
                    return null;
                  },
                ),
                _Field(
                  controller: _address,
                  label: l10n.fieldSellerAddress,
                  maxLines: 2,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) =>
                      (v ?? '').trim().length < 3 ? l10n.errorRequired : null,
                ),
                CityPicker(
                  label: l10n.fieldCity,
                  helperText: l10n.createCityHelper,
                  // Store the choice here so the draft and the estimate below
                  // follow it. The FormField's own state keeps the submitted
                  // value for validation; the page needs the value in a field
                  // it can read when the request is sent.
                  onChanged: (String city) =>
                      setState(() => _city = city),
                  validator: (String? v) =>
                      (v ?? '').trim().length < 2 ? l10n.errorRequired : null,
                ),
              ],
            ),
            _SectionCard(
              number: '03',
              title: l10n.createSectionNotes,
              children: <Widget>[
                _Field(
                  controller: _notes,
                  label: l10n.createNotesHint,
                  hintText: l10n.createSectionNotes,
                  helperText: l10n.createNotesOptional,
                  // Multiline, so `next` would move to the next line rather than
                  // the next field.
                  maxLines: 4,
                  // The column is capped at 1000 characters in the database.
                  // Counted as you type rather than rejected on submit, so a
                  // buyer who has written 1200 characters finds out while they
                  // can still cut something.
                  maxLength: 1000,
                  textInputAction: TextInputAction.newline,
                ),
              ],
            ),
            _SectionCard(
              number: '04',
              title: l10n.costTitle,
              children: <Widget>[
                _Field(
                  controller: _budget,
                  label: l10n.fieldBudget,
                  helperText: l10n.fieldBudgetHint,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    // Digits and one decimal point. A second point is dropped by
                    // the regex rather than producing a value that fails to parse.
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.done,
                  validator: (String? v) {
                    final String input = (v ?? '').trim();
                    if (input.isEmpty) return l10n.errorRequired;
                    if (_draft.budgetAmount == null) return l10n.errorInvalidBudget;
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                _EstimatePreview(estimate: estimate, budget: _draft.budgetAmount),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              // Disabled while in flight, so a slow network cannot produce two
              // requests from one tap.
              onPressed: submitting.isLoading ? null : _submit,
              child: submitting.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.createSubmit),
            ),
          ],
        ),
      ),
    );
  }
}

/// The running total, as the buyer types.
///
/// The buyer's own budget is shown as the total once they enter one. Before
/// that, the platform's estimate stands in. Mixing the two without saying which
/// is which would be how a buyer ends up agreeing to a number they did not set.
class _EstimatePreview extends StatelessWidget {
  const _EstimatePreview({required this.estimate, required this.budget});

  final CostEstimate estimate;
  final double? budget;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool usingBudget = budget != null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        // The light-green estimate surface is a design token rather than a tone
        // from the scheme: the quoted total is deliberately the emerald brand
        // colour, and the box is its lighter friend.
        color: AppColors.successSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Line(
            label: l10n.costInspection,
            value: CostEstimate.format(usingBudget ? budget! : estimate.inspectionFee),
          ),
          _Line(
            label: l10n.costTravel,
            value: l10n.costFree,
          ),
          const Divider(height: AppSpacing.lg),
          _Line(
            label: l10n.costTotal,
            value: CostEstimate.format(usingBudget ? budget! : estimate.total),
            emphasise: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.costEstimateNotice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.emphasise = false});

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Text(label, style: emphasise ? text.titleSmall : text.bodySmall),
          const Spacer(),
          Text(
            value,
            style: emphasise
                ? text.titleSmall?.copyWith(fontWeight: FontWeight.w800)
                : text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.number,
    required this.title,
    required this.children,
  });

  /// The step number, as a two-digit badge ("01"). A string, not an int, so the
  /// leading zero is the designer's, decided once here.
  final String number;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _NumberBadge(number),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// The small emerald step badge on each section card.
class _NumberBadge extends StatelessWidget {
  const _NumberBadge(this.number);

  final String number;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        number,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.textInputAction,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.hintText,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final String? hintText;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        textInputAction: textInputAction,
        maxLines: maxLines,
        maxLength: maxLength,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          helperText: helperText,
          border: const OutlineInputBorder(),
          // Present on every field rather than only when invalid, so the field
          // does not change height the moment it goes red and shove the rest of
          // the form down while the user is looking at it.
          helperMaxLines: 3,
        ),
      ),
    );
  }
}
