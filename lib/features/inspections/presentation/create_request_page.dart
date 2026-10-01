import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../cities/presentation/city_picker.dart';
import '../application/inspection_controller.dart';
import '../data/inspection_repository.dart';
import '../domain/inspection_draft.dart';
import 'widgets/design_widgets.dart';

/// Screen 2: the create-request form.
///
/// RTL, because the reference's `.sc` for this screen is an `.rtl` container:
/// every label, field and card hugs the right edge, and the back square sits at
/// the physical right of the header. [RtlRegion] wraps the whole screen so that
/// is a property of the screen rather than of each row in it.
///
/// Two design facts this screen has to hold on to, because both are easy to lose
/// in a rewrite:
///
///  * **There is no budget input.** The reference has three fixed fee lines and a
///    total, and no field a buyer types a number into. The budget that used to
///    live here has gone; [InspectionDraft.toRow] records the estimate instead.
///  * **The total line is a suffix, not a prefix.** The reference writes
///    `199 ر.س + رسوم المركز` — the figure, then the currency, then the words.
///    [CostEstimate.formatPrefixed] would print it the other way round.
///
/// A `Form` with an explicit key rather than per-field `onChanged` validation,
/// because the submit button has to know whether it may be pressed. Validating
/// only on submit makes the button look broken when the buyer is not done;
/// validating on every keystroke makes a half-typed year light up red.
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
  final TextEditingController _plate = TextEditingController();
  final TextEditingController _listing = TextEditingController();
  final TextEditingController _sellerName = TextEditingController();
  final TextEditingController _sellerPhone = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  /// The chosen canonical city — a value, not a controller, because it comes from
  /// the [CityPicker] sheet rather than from a cursor. Null until the buyer makes
  /// a choice, which is what the validator flags.
  String? _city;

  @override
  void dispose() {
    // Every controller this state creates has to be disposed here. They are
    // created once per State, not once per build, so the usual place to leak them
    // is a StatefulWidget that gets rebuilt rather than recreated.
    for (final TextEditingController c in <TextEditingController>[
      _make,
      _model,
      _year,
      _plate,
      _listing,
      _sellerName,
      _sellerPhone,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  InspectionDraft get _draft => InspectionDraft(
    carMake: _make.text,
    carModel: _model.text,
    carYear: _year.text,
    plateNumber: _plate.text,
    listingUrl: _listing.text,
    sellerName: _sellerName.text,
    sellerPhone: _sellerPhone.text,
    city: _city ?? '',
    clientNotes: _notes.text,
  );

  /// The three fixed fees, before any inspector is involved.
  ///
  /// Not read from the selected city: there is one price list, so varying the
  /// numbers by city would imply a pricing model the schema does not have.
  /// [CostEstimate.standard] is the single source, which is what keeps the figure
  /// on this screen and the figure on the buyer's invoice from drifting.
  CostEstimate get _estimate => CostEstimate.standard;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // The year's field validator has already rejected anything unparseable, and it
    // reads this same getter, so reaching here with a null year would mean the two
    // disagree — which is a bug in this build rather than a thing the buyer did.
    // The check stays because the alternative is sending a request with no year in
    // it, and a guard that is unreachable beats a database rejection the buyer
    // cannot read.
    final InspectionDraft draft = _draft;
    if (draft.year == null) return;

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
      // state to its initial value and turns every specific error into the generic
      // one.
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

    return Scaffold(
      body: RtlRegion(
        child: Column(
          children: <Widget>[
            _CreateHeader(
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                // The canvas, not white: the reference's `.body` for this screen
                // is the one that keeps the page colour, where screens 1, 3 and 4
                // all switch it to white. The three white screens have cards to
                // sit on; this one is a stack of grey fields.
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.inset),
                  children: <Widget>[
                    _CarCard(
                      make: _make,
                      model: _model,
                      year: _year,
                      plate: _plate,
                      listing: _listing,
                      city: _city ?? '',
                      onCity: (String value) =>
                          setState(() => _city = value),
                      // A reader, not a draft: the page re-reads its own draft
                      // inside the validator, and typing does not rebuild the
                      // page, so a draft captured here would be the one from
                      // before the buyer touched the keyboard.
                      parsedYear: () => _draft.year,
                    ),
                    _SellerCard(
                      name: _sellerName,
                      phone: _sellerPhone,
                    ),
                    _NotesCard(notes: _notes),
                    _CostBox(estimate: _estimate),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      // Disabled while in flight, so a slow network cannot produce
                      // two requests from one tap.
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
            ),
          ],
        ),
      ),
    );
  }
}

/// The dark header: a back square, then the title and its stage line.
///
/// The square carries the reference's own `→` glyph rather than Material's
/// `arrow_back`. Under RTL a `→` drawn by the app's own font points at the
/// right edge, which is where the design puts it, and `Icons.arrow_back` would be
/// auto-mirrored by Flutter into a left-pointing arrow — the wrong direction for
/// this screen. [LtrRegion] pins the glyph so the mirroring cannot happen.
class _CreateHeader extends StatelessWidget {
  const _CreateHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return DarkHeader(
      child: Row(
        children: <Widget>[
          Semantics(
            button: true,
            label: l10n.createBack,
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.darkSquare,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const LtrRegion(
                  child: Text(
                    '→',
                    style: TextStyle(
                      fontSize: 20,
                      height: 1.2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.createTitle, style: AppText.onDark(19)),
                const SizedBox(height: 3),
                Text(
                  l10n.createStage1,
                  style: AppText.secondary(12, color: AppColors.onDarkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `🚘 بيانات السيارة المطلوب فحصها` — the car, the city, the plate, the link.
///
/// The reference shows one full-width field for the car, then a `.two` of city
/// (flex 1.3) and plate, then a full-width URL field. This keeps that layout and
/// splits the car across three fields inside the first one — see
/// [CarFields] for why the schema's three columns win over the reference's single
/// `نوع وموديل السيارة`.
class _CarCard extends StatelessWidget {
  const _CarCard({
    required this.make,
    required this.model,
    required this.year,
    required this.plate,
    required this.listing,
    required this.city,
    required this.onCity,
    required this.parsedYear,
  });

  final TextEditingController make;
  final TextEditingController model;
  final TextEditingController year;
  final TextEditingController plate;
  final TextEditingController listing;
  final String city;
  final ValueChanged<String> onCity;

  /// Read by the year's validator, which has to parse rather than pattern-match:
  /// the field accepts Arabic-Indic digits that look like a number and are not one
  /// to `int.parse`. A reader rather than a draft, so it cannot go stale while
  /// the buyer is typing — see [CarFields.parsedYear].
  final int? Function() parsedYear;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return TitledCard(
      title: l10n.cardCarTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CarFields(
            make: make,
            model: model,
            year: year,
            parsedYear: parsedYear,
          ),
          const SizedBox(height: AppSpacing.xs),
          // Each side is a Column because the reference's `.two` cells are a
          // label above a field, and two labels at one height would need both
          // fields to start at the same y — which they do not, because the city
          // picker is a `FormField` with its own internal padding.
          TwoUp(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FieldLabel(l10n.createCityLabel),
                  CityPicker(
                    // The reference's `.fld v`, not the Material decorated field:
                    // this is a designed screen, and a floating label over a grey
                    // fill with a Material expand chevron is the app's old form
                    // language showing up where the design has its own.
                    design: true,
                    label: l10n.createCityLabel,
                    initialValue: city,
                    onChanged: onCity,
                    validator: (String? v) =>
                        (v ?? '').trim().length < 2 ? l10n.errorRequired : null,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FieldLabel(l10n.createPlateLabel),
                  DesignTextField(
                    controller: plate,
                    hintText: l10n.createPlateHint,
                    textInputAction: TextInputAction.next,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FieldLabel(l10n.createListingLabel),
          DesignTextField(
            controller: listing,
            hintText: l10n.createListingHint,
            // The reference marks this field `.ltr`. A URL is a left-to-right
            // string, and letting the bidi algorithm lay it out against an
            // RTL paragraph puts the scheme at the wrong end.
            ltr: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
          ),
        ],
      ),
    );
  }
}

/// The three car fields, under the reference's single `نوع وموديل السيارة` label.
///
/// The reference has one field holding make, model and year together. The schema
/// has three columns and the report tiles want them apart, and gluing three
/// columns into one text field would mean parsing a sentence at query time. So the
/// label is kept verbatim and the fields are split under it, with the reference's
/// own example (`مثال: تويوتا أف جى 2023`) divided across the three hints rather
/// than a new set of placeholder words invented for it.
class CarFields extends StatelessWidget {
  const CarFields({
    required this.make,
    required this.model,
    required this.year,
    required this.parsedYear,
    super.key,
  });

  final TextEditingController make;
  final TextEditingController model;
  final TextEditingController year;

  /// Reads the year the way the draft will read it — parse, range check, null on
  /// anything unparseable — so the validator reports the same verdict the submit
  /// path acts on.
  ///
  /// A *function*, not the draft itself, and that is the whole point. Typing does
  /// not rebuild this card: the controllers notify the fields they belong to, not
  /// the page above them. A draft passed by value is therefore whatever the draft
  /// said the last time the page did rebuild, which is before the buyer typed
  /// anything — so a year of `1949` validated clean, and the submit then bailed on
  /// its own re-check with nothing on screen to say why. A stale read is worse
  /// than no validation, because the button still moves.
  final int? Function() parsedYear;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FieldLabel(l10n.createCarTypeLabel),
        DesignTextField(
          controller: make,
          hintText: l10n.createCarTypeHint,
          textInputAction: TextInputAction.next,
          validator: (String? v) =>
              (v ?? '').trim().isEmpty ? l10n.errorRequired : null,
        ),
        const SizedBox(height: AppSpacing.md),
        FieldLabel(l10n.createCarModelLabel),
        DesignTextField(
          controller: model,
          hintText: l10n.createCarModelHint,
          textInputAction: TextInputAction.next,
          validator: (String? v) =>
              (v ?? '').trim().isEmpty ? l10n.errorRequired : null,
        ),
        const SizedBox(height: AppSpacing.md),
        FieldLabel(l10n.createCarYearLabel),
        DesignTextField(
          controller: year,
          hintText: l10n.createCarYearHint,
          // Digits only. A year is four numbers, and a keyboard offering letters
          // for it is a keyboard offering the wrong suggestion.
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          textInputAction: TextInputAction.next,
          validator: (String? v) {
            final String input = (v ?? '').trim();
            if (input.isEmpty) return l10n.errorRequired;
            if (parsedYear() == null) return l10n.errorInvalidYear;
            return null;
          },
        ),
      ],
    );
  }
}

/// `👤 بيانات البائع للتنسيق الفوري` — the seller card.
///
/// The design has exactly two fields here, a name and a phone. It had three in an
/// earlier draft of this app, one of which was the seller's address; the reference
/// has no address field, and the city is what scopes the request, so the address
/// field is gone and so is the column being written from it.
class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.name, required this.phone});

  final TextEditingController name;
  final TextEditingController phone;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: TitledCard(
        title: l10n.cardSellerTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FieldLabel(l10n.createSellerNameLabel),
            DesignTextField(
              controller: name,
              hintText: l10n.createSellerNameHint,
              textInputAction: TextInputAction.next,
              validator: (String? v) =>
                  (v ?? '').trim().isEmpty ? l10n.errorRequired : null,
            ),
            const SizedBox(height: AppSpacing.md),
            FieldLabel(l10n.createSellerPhoneLabel),
            DesignTextField(
              controller: phone,
              hintText: l10n.createSellerPhoneHint,
              // The reference marks this field `.ltr`: a phone number is
              // left-to-right digits, and under RTL the leading `+` or `0` ends up
              // at the far side of the field from where it was typed.
              ltr: true,
              // Not `TextInputType.phone`: that keyboard has no `+`, and a Saudi
              // number that is dialled from abroad almost always needs one.
              keyboardType: TextInputType.text,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                LengthLimitingTextInputFormatter(20),
              ],
              textInputAction: TextInputAction.next,
              validator: (String? v) {
                final String input = (v ?? '').trim();
                if (input.isEmpty) return l10n.errorRequired;
                // The schema requires 5..30 characters. The lower bound is the only
                // one enforced here; an over-long value is the length formatter's
                // job.
                if (input.length < 5) return l10n.errorInvalidPhone;
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// `📝 ملاحظات إضافية للمعاين (اختياري)` — the notes card.
///
/// A taller field than the others, because the reference's `.ta` is 74dp and its
/// hint is a full sentence the buyer is meant to be able to read before typing.
class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.notes});

  final TextEditingController notes;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: TitledCard(
        title: l10n.cardNotesTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FieldLabel(l10n.createNotesLabel),
            DesignTextField(
              controller: notes,
              hintText: l10n.createNotesHint,
              // Multiline, so `next` would move to the next line rather than the
              // next field.
              maxLines: 3,
              // The column is capped at 1000 characters in the database. Counted
              // as the buyer types rather than rejected on submit, so someone who
              // has written 1200 characters finds out while they can still cut
              // something.
              maxLength: 1000,
              textInputAction: TextInputAction.newline,
            ),
          ],
        ),
      ),
    );
  }
}

/// `🔒 هيكلة التكلفة والشفافية (بدون دفع مقدماً)` — the light-green cost box.
///
/// Not the buyer's [InvoiceBox] even though the two share three of their four
/// lines. This one is light green and says "roughly this, and nothing is charged
/// now"; the buyer's is an off-white document that names a centre and asks for
/// agreement. Sharing one widget would make that difference a colour argument, and
/// the two also differ in bullet and type size.
///
/// The reference's three lines, in its order: centre (pending), inspector,
/// platform. The order is not alphabetical and not by size — the centre is first
/// because it is the line the buyer does not know yet, and reading a cost
/// breakdown top-down wants the unknown first.
class _CostBox extends StatelessWidget {
  const _CostBox({required this.estimate});

  final CostEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: CostBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.createCostTitle,
              style: AppText.title(13, color: AppColors.greenDeep),
            ),
            const SizedBox(height: AppSpacing.sm),
            CostLine(
              label: l10n.createCostCentre,
              value: l10n.invoiceCentrePending,
              // The pending marker is the design's own orange warning treatment
              // and it is the only part of this box that is a warning — hence a
              // smaller type size than the two settled figures.
              valueColor: AppColors.warning,
              valueSize: 10,
            ),
            CostLine(
              label: l10n.invoiceInspectorFee,
              value: CostEstimate.format(estimate.inspectorFee),
            ),
            CostLine(
              label: l10n.invoicePlatformFee,
              value: CostEstimate.format(estimate.platformFee),
            ),
            const DashedDivider(color: AppColors.successBorder),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: Text(
                    l10n.createCostTotalLabel,
                    style: AppText.title(12, color: AppColors.greenDeep),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  flex: 3,
                  child: Text(
                    // `199 ر.س + رسوم المركز` — the reference puts the currency
                    // after the figure and then names the part that is not
                    // included. `CostEstimate.format` gives the first half;
                    // `formatPrefixed` would print `ر.س 199` and lose the clause.
                    l10n.createCostTotalValue(
                      CostEstimate.format(estimate.total),
                    ),
                    textAlign: TextAlign.end,
                    style: AppText.title(12, color: AppColors.green),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
