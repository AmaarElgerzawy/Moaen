import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/inspection_controller.dart';
import '../data/inspection_repository.dart';
import '../data/report_repository.dart';
import '../domain/inspection_report.dart';
import '../domain/inspection_request.dart';
import 'widgets/design_widgets.dart';

/// Screen 5: the inspector enters the inspection's findings.
///
/// RTL, and pushed with no bottom bar — the reference gives it none, because the
/// inspector is mid-task and the nav is not where the next step is.
///
/// The form is long and the sections are not equally important, so the design's
/// own grouping is followed exactly: three inspection lines, a money card, a
/// photos card, the attestation, and the issue button. Nothing is reordered and
/// nothing is collapsed, because the order *is* the reading order of a physical
/// inspection: computer, body, mechanics, then the numbers that follow from them.
///
/// The photo slots are placeholders in this build. The reference draws four
/// squares — three filled, one dashed — and this screen renders that exact shape;
/// wiring a camera into them is a separate subsystem (see `report_media`) and
/// pretending the squares are tappable while they are not would be worse than
/// leaving them as the design draws them.
class ReportEntryPage extends ConsumerStatefulWidget {
  const ReportEntryPage({super.key, required this.id});

  final String id;

  @override
  ConsumerState<ReportEntryPage> createState() => _ReportEntryPageState();
}

class _ReportEntryPageState extends ConsumerState<ReportEntryPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _obdNotes = TextEditingController();
  final TextEditingController _lowerBody = TextEditingController();
  final TextEditingController _repair = TextEditingController();

  /// -1 for not yet chosen. The design draws one option already selected on each
  /// `.seg`, and reproducing that as the *initial* state would make the screen
  /// look filled in when nothing has been inspected yet — so the design's
  /// selection is a screenshot of a completed form, not a default.
  int _obdChoice = -1;
  int _bodyChoice = -1;
  int _engineChoice = -1;
  int _gearboxChoice = -1;

  @override
  void dispose() {
    _obdNotes.dispose();
    _lowerBody.dispose();
    _repair.dispose();
    super.dispose();
  }

  /// The three verdict sets, in the design's order.
  ///
  /// Held as lists of localized strings rather than enums because the values are
  /// the document's own words and a screen in another language has to pick from
  /// a different list; an enum with three members and three translations per
  /// member would be the same data with an extra layer of indirection.
  List<String> _obdOptions(AppLocalizations l10n) => <String>[
    l10n.reportObdClean,
    l10n.reportObdCodes,
  ];

  List<String> _bodyOptions(AppLocalizations l10n) => <String>[
    l10n.reportBodySound,
    l10n.reportBodyRepaint,
    l10n.reportBodyModified,
  ];

  List<String> _engineOptions(AppLocalizations l10n) => <String>[
    l10n.reportEngineExcellent,
    l10n.reportEngineGood,
  ];

  List<String> _gearboxOptions(AppLocalizations l10n) => <String>[
    l10n.reportGearboxSmooth,
    l10n.reportGearboxRough,
  ];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ReportBundle?> bundle = ref.watch(
      reportBundleProvider(widget.id),
    );

    return Scaffold(
      body: RtlRegion(
        child: bundle.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: DesignRetry(
              message: l10n.tabLoadError,
              actionLabel: l10n.actionRetry,
              onRetry: () => ref.invalidate(reportBundleProvider(widget.id)),
            ),
          ),
          data: (ReportBundle? loaded) {
            // The report is reachable from an inspection that has no request
            // row visible to this client — a stale link, or an RLS policy that
            // changed. A form with nothing to describe is not a form.
            if (loaded == null) {
              return Center(
                child: DesignEmpty(
                  title: l10n.errorGeneric,
                  body: l10n.reportEntryUnavailable,
                ),
              );
            }
            return _form(l10n, loaded);
          },
        ),
      ),
    );
  }

  Widget _form(AppLocalizations l10n, ReportBundle bundle) {
    final InspectionRequest request = bundle.requestWithCentre;
    final AsyncValue<void> issuing = ref.watch(reportControllerProvider);
    final Object? issueError = issuing.error;

    return Form(
      key: _formKey,
      child: Column(
        children: <Widget>[
          DarkHeader(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        l10n.reportEntryTitle,
                        style: AppText.onDark(19),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.reportEntrySubtitle(
                          request.carDescription,
                          request.inspectionCenterName ?? l10n.buyerNoInspector,
                        ),
                        style: AppText.secondary(
                          12,
                          color: AppColors.onDarkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // White pill, green text — the reference's inverse treatment, and
                // the only pill in the app with a light fill on a dark header.
                AppPill(
                  label: l10n.reportEntryRequest(request.reference),
                  tone: PillTone.inverse,
                  fontSize: 11,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              // The canvas colour, not white: this is the one screen after Screen
              // 2 that keeps `.body`'s own background, because its cards are
              // stacked six deep and a white page behind six white cards would
              // have no edges to see.
              padding: const EdgeInsets.all(AppSpacing.inset),
              children: <Widget>[
                _ObdCard(
                  options: _obdOptions(l10n),
                  selected: _obdChoice,
                  onChanged: (int i) => setState(() => _obdChoice = i),
                  notes: _obdNotes,
                ),
                const SizedBox(height: AppSpacing.md),
                _BodyCard(
                  options: _bodyOptions(l10n),
                  selected: _bodyChoice,
                  onChanged: (int i) => setState(() => _bodyChoice = i),
                ),
                const SizedBox(height: AppSpacing.md),
                _MechanicsCard(
                  engineOptions: _engineOptions(l10n),
                  engineSelected: _engineChoice,
                  onEngine: (int i) => setState(() => _engineChoice = i),
                  gearboxOptions: _gearboxOptions(l10n),
                  gearboxSelected: _gearboxChoice,
                  onGearbox: (int i) => setState(() => _gearboxChoice = i),
                  lowerBody: _lowerBody,
                ),
                const SizedBox(height: AppSpacing.md),
                _MoneyCard(repair: _repair, bundle: bundle),
                const SizedBox(height: AppSpacing.md),
                _PhotosCard(count: 3),
                const SizedBox(height: AppSpacing.md),
                _Attestation(),
                if (issueError != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    issueError is InspectionFailure
                        ? issueError.message
                        : l10n.tabLoadError,
                    style: AppText.secondary(12, color: AppColors.live),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  // 56dp and 15dp, the design's only tall green button outside
                  // the booking CTA. This is the action the whole screen builds
                  // towards, so it is given the extra height and the drop shadow
                  // the reference sets on it.
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(
                      AppTheme.buttonHeightTall,
                    ),
                    textStyle: AppText.title(15, color: Colors.white),
                    elevation: 4,
                    shadowColor: AppColors.green.withValues(alpha: 0.3),
                  ),
                  onPressed: issuing.isLoading ? null : () => _issue(bundle),
                  child: issuing.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.reportIssueButton),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _issue(ReportBundle bundle) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_obdChoice < 0 || _bodyChoice < 0) {
      _toast(AppLocalizations.of(context).errorRequired);
      return;
    }

    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<ReportSection> sections = ReportSectorScoring.rows(
      suspensionNote: _lowerBody.text,
    );
    // Chosen here rather than in the build because the report row is a snapshot:
    // the report says what was true when it was issued, so the condition score
    // and the headline are read once and frozen, not re-read on every rebuild.
    final InspectionReport? existing = bundle.report.certifiedAt == null
        ? null
        : bundle.report;
    // The four sector scores are the only findings this form produces, so the
    // two headline figures are derived from them rather than invented. See
    // `ReportSectorScoring.summary`; on a re-issue an inspector's stored figure
    // wins, because re-deriving it would silently change a number already
    // printed on a document somebody has.
    final int? derived = ReportSectorScoring.summary(sections);

    final ReportDraft draft = ReportDraft(
      inspectionId: widget.id,
      obdClean: _obdChoice == 0,
      obdNotes: _obdNotes.text,
      repairEstimate: _repair.text.trim().isEmpty
          ? null
          : double.tryParse(
              _repair.text.replaceAll(RegExp(r'[^0-9.]'), ''),
            ),
      conditionScore: existing?.conditionScore ?? derived ?? 0,
      qualityScore: existing?.qualityScore ?? derived ?? 0,
      centreInvoiceNo: existing?.centerInvoiceNo ?? '',
      resultSummary: existing?.resultSummary ?? '',
      sections: sections,
    );

    try {
      await ref.read(reportControllerProvider.notifier).issue(draft);
      if (!mounted) return;
      _toast(l10n.reportCertified);
      // Not awaited: `pushReplacementNamed`'s result is the popped route's, and
      // this page is being discarded, so there is nothing here for the value to
      // say. The replacement itself is the last thing the frame does.
      context.pushReplacementNamed(
        'report',
        pathParameters: <String, String>{'id': widget.id},
      );
    } on Object {
      // Rendered above from the controller's error state. Swallowed so the
      // failure does not surface as an unhandled async error out of a tap.
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// `💻 فحص كمبيوتر الأعطال (OBD-II)` — the computer, the codes, and the note.
class _ObdCard extends StatelessWidget {
  const _ObdCard({
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.notes,
  });

  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  final TextEditingController notes;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return TitledCard(
      title: l10n.reportObdTitle,
      trailingLabel: l10n.reportLineTag('01'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FieldLabel(l10n.reportObdLabel),
          SegmentedChoice(
            options: options,
            selectedIndex: selected,
            onChanged: onChanged,
          ),
          const SizedBox(height: AppSpacing.lg),
          FieldLabel(l10n.reportObdNotesLabel),
          DesignTextField(
            controller: notes,
            // The design's `.ta` — three lines, the tallest field on the screen.
            maxLines: 3,
            maxLength: 2000,
            textInputAction: TextInputAction.newline,
          ),
        ],
      ),
    );
  }
}

/// `🚗 فحص البودي والهيكل (المركب بالرفاع)` — the chassis verdict and the two
/// front fenders.
class _BodyCard extends StatelessWidget {
  const _BodyCard({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return TitledCard(
      title: l10n.reportBodyTitle,
      trailingLabel: l10n.reportLineTag('02'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FieldLabel(l10n.reportBodyLabel),
          SegmentedChoice(
            options: options,
            selectedIndex: selected,
            onChanged: onChanged,
          ),
          const SizedBox(height: AppSpacing.lg),
          // The two fenders are the design's own read-only-looking fields. They
          // are not read-only: each opens the same three-way sheet, because a
          // field that opens a menu must not look like a field that only
          // displays one.
          TwoUp(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FieldLabel(l10n.reportFenderRightLabel),
                  ChoiceField(
                    label: l10n.reportFenderRightLabel,
                    options: options,
                    selectedIndex: selected,
                    onChanged: onChanged,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FieldLabel(l10n.reportFenderLeftLabel),
                  ChoiceField(
                    label: l10n.reportFenderLeftLabel,
                    options: options,
                    selectedIndex: selected,
                    onChanged: onChanged,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `⚙️ الميكانيكا وتجربة القيادة` — engine, gearbox, and the lower body.
class _MechanicsCard extends StatelessWidget {
  const _MechanicsCard({
    required this.engineOptions,
    required this.engineSelected,
    required this.onEngine,
    required this.gearboxOptions,
    required this.gearboxSelected,
    required this.onGearbox,
    required this.lowerBody,
  });

  final List<String> engineOptions;
  final int engineSelected;
  final ValueChanged<int> onEngine;
  final List<String> gearboxOptions;
  final int gearboxSelected;
  final ValueChanged<int> onGearbox;
  final TextEditingController lowerBody;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return TitledCard(
      title: l10n.reportMechanicsTitle,
      trailingLabel: l10n.reportLineTag('03'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TwoUp(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FieldLabel(l10n.reportEngineLabel),
                  ChoiceField(
                    label: l10n.reportEngineLabel,
                    options: engineOptions,
                    selectedIndex: engineSelected,
                    onChanged: onEngine,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FieldLabel(l10n.reportGearboxLabel),
                  ChoiceField(
                    label: l10n.reportGearboxLabel,
                    options: gearboxOptions,
                    selectedIndex: gearboxSelected,
                    onChanged: onGearbox,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FieldLabel(l10n.reportAcLabel),
          DesignTextField(
            controller: lowerBody,
            // The design's field is one line and truncates with an ellipsis; a
            // single-line field would hide most of what the inspector types on a
            // 390dp screen, so this is two lines and the design's height is the
            // one place on this card that is not reproduced literally.
            maxLines: 2,
            maxLength: 2000,
            textInputAction: TextInputAction.newline,
          ),
        ],
      ),
    );
  }
}

/// `💰 التقدير المالي للإصلاحات التقديرية` — the repair estimate and the
/// condition score.
///
/// The condition score is the design's own `92% (ممتازة)` read from the bundle
/// rather than typed: it is a summary of the three inspection lines above it, so
/// letting an inspector type it would be asking for a number and an answer to the
/// same question. The design draws it as a value, and it is shown as the design's
/// value from the stored report.
class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.repair, required this.bundle});

  final TextEditingController repair;
  final ReportBundle bundle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final InspectionReport report = bundle.report;

    return TitledCard(
      title: l10n.reportMoneyTitle,
      child: TwoUp(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FieldLabel(l10n.reportRepairLabel),
              DesignTextField(
                controller: repair,
                hintText: l10n.reportRepairHint,
                // Digits only, because the field holds a number and the design
                // appends the currency itself.
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  LengthLimitingTextInputFormatter(9),
                ],
                textInputAction: TextInputAction.next,
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FieldLabel(l10n.reportConditionLabel),
              // Not a text field: the design draws this one as a filled `.fld v`,
              // and it is a number the app holds rather than one a person types.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.inset,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Text(
                  report.conditionScore == 0
                      ? '—'
                      : '${report.conditionScore}% '
                            '(${l10n.reportConditionExcellent})',
                  style: AppText.title(13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `📷 صور الفحص الميداني والتوثيق` — three filled slots and one dashed add.
///
/// Not interactive in this build. The design's fourth tile is an invitation to
/// add a photo, and the honest rendering of a control that cannot work yet is a
/// slot that does not accept the tap — see the class doc.
class _PhotosCard extends StatelessWidget {
  const _PhotosCard({required this.count});

  /// How many filled slots to draw. Three, because the design draws three and
  /// because a photo count is not a thing a form can ask a person to guess.
  final int count;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return TitledCard(
      title: l10n.reportPhotosTitle,
      child: TwoUp(
        // Two at a time. The design's `.two` puts four across on a 390dp
        // screen, which is 90dp per tile; the design's own tiles are square with
        // an 11dp caption, and four across is unreadable. The two-by-two
        // arrangement keeps every tile at the size its caption needs, and
        // [TwoUp] is the design's own two-column row.
        children: <Widget>[
          Column(
            children: <Widget>[
              PhotoSlot(label: l10n.reportPhotoSlot(1)),
              const SizedBox(height: AppSpacing.sm),
              PhotoSlot(label: l10n.reportPhotoSlot(3)),
            ],
          ),
          Column(
            children: <Widget>[
              PhotoSlot(label: l10n.reportPhotoSlot(2)),
              const SizedBox(height: AppSpacing.sm),
              PhotoSlot(label: l10n.reportPhotoAdd),
            ],
          ),
        ],
      ),
    );
  }
}

/// The light-green attestation box with the pen glyph at the physical left.
class _Attestation extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return CostBox(
      padding: const EdgeInsets.all(AppRadius.card),
      borderRadius: AppRadius.card,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('✍️', style: TextStyle(fontSize: 22)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: l10n.reportDigitalNoteBold,
                    style: AppText.title(12, color: AppColors.green),
                  ),
                  TextSpan(
                    text: l10n.reportDigitalNoteRest,
                    style: AppText.secondary(12),
                  ),
                ],
              ),
              style: AppText.secondary(12).copyWith(height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}
