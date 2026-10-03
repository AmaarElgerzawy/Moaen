import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/pricing/commission.dart';
import '../../../core/pricing/commission_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../cities/application/city_controller.dart';
import '../../cities/data/city_repository.dart';
import '../../cities/presentation/city_picker.dart';
import '../application/inspection_controller.dart';
import '../data/inspection_repository.dart';
import '../data/location_surface.dart';
import '../domain/custom_centre.dart';
import '../domain/inspection_draft.dart';
import 'widgets/design_widgets.dart';
import 'widgets/location_picker.dart';

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
///  * **The budget is what the buyer types, and the three lines below it are that
///    number broken down.** The reference had three fixed fee lines and a total with
///    no field to change any of them; migration 0011 gave the buyer a budget and the
///    platform a commission that can be a percentage, so a fixed total would now be a
///    figure the database contradicts. [CostBox] keeps the design's three lines, the
///    dashed rule and the `+ centre fee` suffix — it is fed the typed budget and the
///    live commission instead of the design's placeholder figures.
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
  final TextEditingController _centreName = TextEditingController();

  /// The budget the buyer proposes.
  ///
  /// Seeded with [CostEstimate.defaultBudget] rather than left empty. A prefilled
  /// field makes the page's first impression a price instead of a blank, and this one
  /// is editable in a keystroke — whereas an empty field under a "you must fill this
  /// in" rule makes a buyer who was happy with the platform's standing figure type out
  /// the same number to find out what it was.
  final TextEditingController _budget = TextEditingController(
    text: CostEstimate.defaultBudget.toStringAsFixed(0),
  );

  /// The chosen canonical city — a value, not a controller, because it comes from
  /// the [CityPicker] sheet rather than from a cursor. Null until the buyer makes
  /// a choice, which is what the validator flags.
  String? _city;

  /// Whether the buyer is naming a centre of their own.
  ///
  /// False is the default and the common case, and it is what makes this card
  /// additive: a buyer with no preference never sees the extra fields, and the
  /// request they file is indistinguishable from one filed before this card
  /// existed. True switches the card from one line to three.
  bool _wantsCustomCentre = false;

  /// The point the buyer dropped on the map, or null.
  ///
  /// Held beside [_wantsCustomCentre] rather than replacing it, so switching back
  /// to an approved centre and forward again keeps the name and the pin. Losing
  /// them on a toggle would make the choice expensive to try, and this is a
  /// preference — the least costly thing for a buyer to change their mind about.
  LatLng? _centrePoint;

  /// Whether the buyer has pressed submit at least once.
  ///
  /// The card's completeness error is only useful once they have tried to send the
  /// form, which is the same contract every `Form` validator in this page works
  /// under — errors appear on submit, not on arrival. Without it the card would
  /// greet every buyer with an error about a preference they have not expressed.
  bool _submitAttempted = false;

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
      _centreName,
      _budget,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The typed budget, or null when it is not a number at all.
  ///
  /// Parsed from the controller rather than held as a double, for the same reason the
  /// year field is a string: the text between two keystrokes is not a number, and
  /// keeping the text and the parsed value in step would need a listener whose only
  /// job is to disagree with the field the buyer is looking at.
  double? get _budgetValue => double.tryParse(_budget.text.trim());

  /// What the typed budget passes to the database.
  ///
  /// Falls back to [CostEstimate.defaultBudget] while the field is mid-edit, so the
  /// cost box below keeps rendering a sensible split instead of an empty one on every
  /// keystroke. The validator is what refuses an unfilled or out-of-range budget; this
  /// is only so the card can be drawn at all.
  double get _shownBudget {
    final double? typed = _budgetValue;
    if (typed == null) return CostEstimate.defaultBudget;
    if (typed < CostEstimate.minBudget) return CostEstimate.minBudget;
    if (typed > CostEstimate.maxBudget) return CostEstimate.maxBudget;
    return typed;
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
    budget: _budgetValue ?? CostEstimate.defaultBudget,
    customCentre: _customCentre,
  );

  /// The buyer's suggestion, or null when they have not named one or named one
  /// incompletely.
  ///
  /// Null rather than a half-built [CustomCentre] when either field is missing,
  /// because migration 0010's shape constraint refuses a name without a location
  /// and the form's job is to keep the database from ever seeing one. Building it
  /// from whatever is typed would turn a half-finished card into a rejected
  /// request; this way it is simply not a suggestion yet, and the card says which
  /// half is missing.
  CustomCentre? get _customCentre {
    if (!_wantsCustomCentre) return null;
    final String name = _centreName.text.trim();
    final LatLng? point = _centrePoint;
    if (point == null) return null;
    final CustomCentre candidate = CustomCentre(
      name: name,
      latitude: point.latitude,
      longitude: point.longitude,
    );
    // `isComplete` covers the name's length bounds as well as the coordinate
    // ranges, so a one-character name is not sent to be rejected by a constraint.
    return candidate.isComplete ? candidate : null;
  }

  /// The three fixed fees, before any inspector is involved.
  ///
  /// Read from the live `platform_settings` row rather than from
  /// [CostEstimate.standard], because the commission is an admin's to change and a
  /// create form quoting 49 while the platform charges 10% would be a form that tells
  /// the buyer the wrong price. The fallback is [Commission.defaultFixedValue], which
  /// is also what the row is seeded with, so a failed read shows the platform's
  /// standing figure rather than an empty card — and the number that actually lands on
  /// the row is snapshotted by the database from the table, not from anything here.
  Commission get _commission =>
      ref.watch(commissionProvider).value ?? const Commission();

  Future<void> _submit() async {
    final bool formValid = _formKey.currentState?.validate() ?? false;

    // The custom centre is not a `Form` field — its three halves are a choice, a
    // name and a map, and only one of those is a text field — so the form cannot
    // flag an incomplete one and it is checked here.
    //
    // It blocks the submit rather than being quietly dropped, because the buyer
    // chose "Another centre" and a request that filed with no centre named would be
    // them believing they had expressed a preference they had not. Preferring no
    // centre is the *absence* of [_wantsCustomCentre]; that must stay a valid
    // request, so only the true branch above is a failure.
    final bool centreValid = !_wantsCustomCentre || _customCentre != null;

    if (!formValid || !centreValid) {
      // Setting this makes the card show what is missing. It has to be a rebuild,
      // because `validate()` on its own only marks text fields dirty and would
      // leave the card's error invisible.
      if (mounted) setState(() => _submitAttempted = true);
      return;
    }

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
                    _CustomCentreCard(
                      wantsCustom: _wantsCustomCentre,
                      name: _centreName,
                      point: _centrePoint,
                      city: _city ?? '',
                      onToggle: (bool value) => setState(
                        () => _wantsCustomCentre = value,
                      ),
                      onPoint: (LatLng value) =>
                          setState(() => _centrePoint = value),
                      // Shown only after a submit that failed, and only while the
                      // buyer has actually chosen the custom option. Reporting an
                      // incomplete card before they have touched it would put an
                      // error on a form nobody has filled in yet.
                      error: _submitAttempted && _wantsCustomCentre &&
                              _customCentre == null
                          ? l10n.customCentreBuyerIncomplete
                          : null,
                    ),
                    _CostBox(
                      controller: _budget,
                      budget: _shownBudget,
                      commission: _commission,
                      onBudgetChanged: () => setState(() {}),
                    ),
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

/// `📍 مركز الفحص` — the buyer's optional centre suggestion.
///
/// **Not part of the approved design.** The reference's create-request screen is
/// four cards and a button, and none of them is a centre: in the design the
/// inspector picks the centre during the 48-hour coordination window. This card
/// exists because a city with no approved centre leaves that window with nothing to
/// pick, and because a buyer who knows a good shop should be able to say so. It is
/// additive and skippable — a buyer who touches nothing here files exactly the
/// request they filed before.
///
/// The card is collapsed to a single explanatory line until [wantsCustom] is true,
/// so the common case costs one line rather than three fields.
class _CustomCentreCard extends ConsumerWidget {
  const _CustomCentreCard({
    required this.wantsCustom,
    required this.name,
    required this.point,
    required this.city,
    required this.onToggle,
    required this.onPoint,
    required this.error,
  });

  final bool wantsCustom;

  final TextEditingController name;
  final LatLng? point;

  /// The request's city, used to centre the map. Empty until the buyer has chosen.
  final String city;

  final ValueChanged<bool> onToggle;
  final ValueChanged<LatLng> onPoint;

  /// Shown after a failed submit, while the card is incomplete.
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: TitledCard(
        title: l10n.cardCentreTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.customCentreIntro,
              style: AppText.secondary(13),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedChoice(
              options: <String>[
                l10n.customCentreChoiceApproved,
                l10n.customCentreChoiceCustom,
              ],
              selectedIndex: wantsCustom ? 1 : 0,
              onChanged: (int index) => onToggle(index == 1),
            ),
            // `AnimatedSize` would be smoother, and is left out: the card's height
            // change is small and a submit button that slides under a buyer's thumb
            // mid-tap is a worse outcome than an instant reveal. The reference has no
            // such transition anywhere, so an abrupt one is also the more faithful
            // read of a design that switches instantly.
            if (wantsCustom) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              FieldLabel(l10n.customCentreNameLabel),
              DesignTextField(
                controller: name,
                hintText: l10n.customCentreNameHint,
                // Capped at the same 120 the database enforces, so the field
                // cannot accumulate a name that a constraint would later reject.
                maxLength: 120,
              ),
              const SizedBox(height: AppSpacing.md),
              _CityAnchoredLocationField(
                value: point,
                city: city,
                onChanged: onPoint,
              ),
            ],
            if (error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                error!,
                style: AppText.secondary(13, color: AppColors.live),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// [LocationField] anchored on the request's own city.
///
/// The anchor is a `FutureProvider` read rather than a value the page already has,
/// because the city is a free-text string on the request and its coordinate lives
/// on a different row of `cities`. Watching it here keeps that lookup out of
/// `_CreateRequestPageState`, which has no reason to know the map opens on
/// coordinates.
///
/// While it loads, and if it fails, the field opens on [kFallbackCentre]. A city
/// with no coordinate is a row someone added by hand rather than an error, and the
/// map still works — it just opens somewhere the person has to pan from.
class _CityAnchoredLocationField extends ConsumerWidget {
  const _CityAnchoredLocationField({
    required this.value,
    required this.city,
    required this.onChanged,
  });

  final LatLng? value;
  final String city;
  final ValueChanged<LatLng> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched on an empty city too, which resolves to null immediately without a
    // query: `coordinatesOf('')` matches no row. That keeps the provider tree
    // uniform instead of switching between a watched and an unwatched read.
    final CityCoordinates? anchor = ref.watch(
      cityCoordinatesProvider(city),
    ).value;

    return LocationField(
      value: value,
      initial: anchor == null
          ? kFallbackCentre
          : LatLng(anchor.latitude, anchor.longitude),
      onChanged: onChanged,
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
/// The buyer's budget, and what that budget is made of.
///
/// The field and the box are one widget because the three lines below the field are a
/// breakdown of the number above it. Splitting them would put two independently
/// laid-out cards on the page where the reader has to hold one number in their head
/// while their eye moves between them — and the whole point of showing the split is
/// that the buyer should not have to.
class _CostBox extends StatelessWidget {
  const _CostBox({
    required this.controller,
    required this.budget,
    required this.commission,
    required this.onBudgetChanged,
  });

  final TextEditingController controller;

  /// The buyer's typed budget, already clamped by the page.
  final double budget;

  final Commission commission;

  /// Rebuilds the page, so the three lines below re-read the field.
  ///
  /// A plain callback rather than a `ValueListenableBuilder` around the lines: the
  /// page's `_shownBudget` already clamps the value and the page is going to rebuild
  /// for its own reasons anyway, so a second listener here would be a second place
  /// that has to agree about what "the current budget" means.
  final VoidCallback onBudgetChanged;

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
            const SizedBox(height: AppSpacing.md),
            FieldLabel(l10n.fieldBudget),
            DesignTextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              // Left-aligned and forced left-to-right even on the Arabic screen: the
              // digits are Western throughout this app, and a number laid out against
              // an RTL paragraph puts its units at the wrong end of itself.
              ltr: true,
              hintText: l10n.fieldBudgetHint,
              // `TextFormField` under the hood, so this takes part in the page's
              // `Form` and prints its own error — no hand-drawn one here, which is
              // how the other five fields on this page behave.
              validator: (String? value) => _validateBudget(context, value),
              onChanged: (_) => onBudgetChanged(),
            ),
            const SizedBox(height: AppSpacing.md),
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
              value: CostEstimate.format(commission.netFor(budget)),
            ),
            CostLine(
              label: l10n.invoicePlatformFee,
              value: CostEstimate.format(commission.feeFor(budget)),
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
                    l10n.createCostTotalValue(CostEstimate.format(budget)),
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

/// The budget field's three failure messages.
///
/// Distinct rather than one "invalid", because they are three different mistakes:
/// something that is not a number at all, a number below the column's floor, and one
/// above its ceiling. A buyer who typed `5000SAR` needs to be told to drop the
/// letters; a buyer who typed `20` needs to be told there is a floor. Both used to
/// get the same sentence, which was the card's only validation message.
///
/// The bounds are [CostEstimate]'s, the same constants the column's check constraint
/// is built from — a range message that disagreed with the column would tell a buyer
/// a limit the database does not have.
String? _validateBudget(BuildContext context, String? raw) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final String trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return l10n.budgetNotANumber;

  final double? amount = double.tryParse(trimmed);
  if (amount == null) return l10n.budgetNotANumber;
  if (amount < CostEstimate.minBudget) {
    return l10n.budgetTooLow('${CostEstimate.minBudget.round()}');
  }
  if (amount > CostEstimate.maxBudget) {
    return l10n.budgetTooHigh('${CostEstimate.maxBudget.round()}');
  }
  return null;
}
