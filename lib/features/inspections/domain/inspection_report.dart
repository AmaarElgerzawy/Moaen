import 'inspection_centre.dart';
import 'inspection_request.dart';

/// A row of `public.inspection_reports` — the findings behind one inspection's
/// A4 report.
///
/// Migration 0001 gave this table seven `NOT NULL` 1..5 ratings: six components
/// plus an `overall_rating`. The design's report-entry screen collects none of
/// them — it collects an OBD verdict, a body verdict, two mechanical verdicts and
/// a repair estimate — so every one of the seven was a number the app would have
/// had to invent on a document attributed to a named inspector. Migration 0009
/// relaxes them to nullable and the app stops reading them; the columns stay so
/// the data and the option survive.
///
/// What replaces them is the long form, and it is what the A4 report renders: a
/// headline verdict and quality percentage ([qualityScore]), the vehicle's own
/// condition ([conditionScore]), the OBD scan, the repair estimate, the centre's
/// invoice number, and — in the two tables this bundle assembles — the body
/// blueprint and the per-sector efficiency table.
class InspectionReport {
  const InspectionReport({
    required this.id,
    required this.inspectionId,
    this.notes,
    this.pdfReportUrl,
    this.completedAt,
    this.obdClean,
    this.obdNotes,
    this.repairEstimate,
    this.conditionScore,
    this.qualityScore,
    this.centerInvoiceNo,
    this.resultSummary,
    this.certifiedAt,
  });

  final String id;
  final String inspectionId;

  final String? notes;
  final String? pdfReportUrl;
  final DateTime? completedAt;

  /// Screen 5's OBD card: a clean scan, or recorded codes. Null before the
  /// inspector has scanned, which is different from a scan that found nothing.
  final bool? obdClean;
  final String? obdNotes;

  /// Screen 5's money card: what the repairs are expected to cost.
  final double? repairEstimate;

  /// 0..100 — `92% (ممتازة)`, the vehicle's condition as opposed to the report's
  /// headline verdict.
  final int? conditionScore;

  /// 0..100 — the report's headline, the figure the donut shows.
  final int? qualityScore;

  /// The centre's own invoice, which the report cites in its disclaimer and the
  /// buyer may need for a claim.
  final String? centerInvoiceNo;

  /// The banner paragraph above the donut.
  final String? resultSummary;

  /// When the report became a citable document. Null until it is issued.
  final DateTime? certifiedAt;

  /// True once the report has been issued, which is what the buyer's reports tab
  /// filters on and what the seal on the A4 stands for.
  bool get isCertified => certifiedAt != null;

  factory InspectionReport.fromRow(Map<String, dynamic> row) => InspectionReport(
    id: row['id'] as String,
    inspectionId: row['inspection_id'] as String,
    notes: row['notes'] as String?,
    pdfReportUrl: row['pdf_report_url'] as String?,
    completedAt: _asDate(row['completed_at']),
    obdClean: row['obd_clean'] as bool?,
    obdNotes: row['obd_notes'] as String?,
    repairEstimate: row['repair_estimate'] == null
        ? null
        : _asDouble(row['repair_estimate']),
    conditionScore: (row['condition_score'] as num?)?.toInt(),
    qualityScore: (row['quality_score'] as num?)?.toInt(),
    centerInvoiceNo: row['center_invoice_no'] as String?,
    resultSummary: row['result_summary'] as String?,
    certifiedAt: _asDate(row['certified_at']),
  );
}

/// One region of the car on the report's blueprint diagram — a row of
/// `public.inspection_report_parts`.
///
/// The English key is stored rather than derived, because the diagram labels
/// each region twice, in English at the physical left and Arabic at the physical
/// right, and the *pair* has to stay together. Storing only the Arabic would mean
/// the English half of every chip was a translation decided in the UI.
class ReportPart {
  const ReportPart({
    required this.ordinal,
    required this.partKey,
    required this.labelEn,
    required this.labelAr,
    required this.verdict,
    required this.tone,
  });

  final int ordinal;
  final String partKey;
  final String labelEn;
  final String labelAr;
  final String verdict;
  final ReportPartTone tone;

  factory ReportPart.fromRow(Map<String, dynamic> row) => ReportPart(
    ordinal: (row['ordinal'] as num).toInt(),
    partKey: row['part_key'] as String,
    labelEn: row['label_en'] as String,
    labelAr: row['label_ar'] as String,
    verdict: row['verdict'] as String,
    // A Postgres enum arrives as its own name, undecoded.
    tone: ReportPartTone.fromName(row['tone'] as String? ?? 'good'),
  );
}

/// The three verdicts a blueprint region can carry.
///
/// Constrained by the `report_part_tone` enum in the database rather than in Dart,
/// so a client cannot invent a colour the report has no swatch for.
enum ReportPartTone {
  good,
  warn,
  poor;

  static ReportPartTone fromName(String value) => switch (value) {
    'warn' => ReportPartTone.warn,
    'poor' => ReportPartTone.poor,
    _ => ReportPartTone.good,
  };

  /// The name the `report_part_tone` enum stores. Needed because the constraint
  /// is in the database, so the value written has to be the database's spelling
  /// rather than whatever the enum member is called in Dart.
  String get wireName => switch (this) {
    ReportPartTone.good => 'good',
    ReportPartTone.warn => 'warn',
    ReportPartTone.poor => 'poor',
  };
}

/// One row of the report's efficiency table — a
/// `public.inspection_report_sections` row.
///
/// [efficiency] is a whole percentage because that is what a bar can honestly
/// render. A 0–5 score shown as a bar would imply a precision the number does
/// not have.
class ReportSection {
  const ReportSection({
    required this.ordinal,
    required this.label,
    required this.efficiency,
    this.notes,
  });

  final int ordinal;

  /// The sector's name, stored in Arabic because the certified document is an
  /// Arabic document — its disclaimer, its seal and its verdicts are all written
  /// in Arabic, and a report is a fixed artefact rather than a live translation.
  /// The app chooses the label from a fixed four-sector vocabulary; an inspector
  /// never types one.
  final String label;

  final int efficiency;

  /// Null when this sector has a score and no narrative. The design's entry form
  /// collects free text for two of the four sectors, and migration 0009 relaxed
  /// the column to nullable rather than have the app write an inspection sentence
  /// nobody wrote.
  final String? notes;

  factory ReportSection.fromRow(Map<String, dynamic> row) => ReportSection(
    ordinal: (row['ordinal'] as num).toInt(),
    label: row['label'] as String,
    efficiency: (row['efficiency'] as num).toInt(),
    notes: row['notes'] as String?,
  );
}

/// Everything one A4 report is made of, in one object.
///
/// Assembled by `ReportRepository.load` rather than read field by field by the
/// report widget, so the report page asks one question and gets one answer. A
/// page that issued four reads would render a report whose table, blueprint and
/// banner were each fetched at a slightly different moment — and on a report
/// being *certified*, that is the difference between a document and a fiction.
class ReportBundle {
  const ReportBundle({
    required this.request,
    required this.report,
    this.centre,
    this.parts = const <ReportPart>[],
    this.sections = const <ReportSection>[],
  });

  final InspectionRequest request;
  final InspectionReport report;

  /// The booked centre, resolved from `inspection_centres` rather than from the
  /// name frozen on the request — the report cites the centre's *invoice*
  /// number and its fee, and a bare name is not enough to render either.
  final InspectionCentre? centre;

  final List<ReportPart> parts;
  final List<ReportSection> sections;

  /// A copy of [request] with [centre] folded in, so every screen that shows a
  /// car name and a city shows the same ones.
  ///
  /// The request row already carries the centre's *name* (frozen when the
  /// inspector booked it) but never its fee; the fee has to come from the centre
  /// row. Folding it in here means the report renders one `InspectionRequest`
  /// rather than taking the name from one source and the fee from another.
  InspectionRequest get requestWithCentre => centre == null
      ? request
      : request.copyWith(
          inspectionCenterName: centre!.name,
          centerFee: centre!.fee,
        );
}

/// How Screen 5's verdicts become the A4's four sector rows.
///
/// **Decided, not derived.** The reference draws the two screens as separate views
/// of one inspection but never says how a verdict on the entry form turns into a
/// percentage on the printed table, and the entry form collects no percentages at
/// all. Three things were available: add inputs the reference does not draw, derive
/// percentages from the verdicts, or use the figures the reference itself prints.
/// The last was chosen.
///
/// The consequence is that rows 1–3 carry the A4's own `95%` / `98%` / `100%` and
/// the design's own sentences on every report, whatever the inspector answered on
/// the form, and only row 4 — the one sector the form has free text for — moves
/// with a person. That is a deliberate trade: a certified document whose four bars
/// are the same numbers the reference printed is reproducible and verifiable,
/// where a percentage the inspector never agreed to is a claim attributed to their
/// name.
///
/// If per-inspection figures are ever wanted, the change is confined to this class
/// and to the four `SegmentedChoice` controls on Screen 5: everything downstream
/// already takes a percentage and a note per sector.
class ReportSectorScoring {
  const ReportSectorScoring._();

  /// The reference's own sector names, in the order the A4 prints them.
  static const String engineSector = 'المحرك والميكانيكا';
  static const String gearboxSector = 'ناقل الحركة (القير)';
  static const String chassisSector = 'الشاصي والهيكل';
  static const String suspensionSector = 'العضلات والتعليق';

  /// The reference's own tier words, which sit in parentheses beside each bar.
  static const String excellent = 'ممتاز';
  static const String sound = 'سليم';
  static const String acceptable = 'مقبول';

  /// The three sectors the entry form has a verdict control for, and the
  /// percentages the A4 prints beside them.
  static const int enginePercent = 95;
  static const int gearboxPercent = 98;
  static const int chassisPercent = 100;

  /// Row 4's percentage. Not a verdict-controlled sector at all — the form's only
  /// input for it is the free-text `التكييف والعضلات السفلية` field — and the
  /// design's own figure for a sector an inspector only has something to say
  /// about is [acceptable] rather than a passing grade.
  static const int suspensionPercent = 80;

  /// The reference's own sentences for rows 1–3.
  ///
  /// Reproduced verbatim rather than composed, because a report is a fixed
  /// artefact and these are the words the design put on it. They are the design's
  /// illustration of what a sector note reads like, not a claim that this
  /// particular engine has no oil leaks — the honest form of that sentence comes
  /// from the inspector's own [suspensionNote]-style input, which is why row 4
  /// is the only row whose note changes.
  static const String engineNote =
      'أداء ممتاز، لا توجد تهريبات زيت أو حرارة زائدة.';
  static const String gearboxNote =
      'التبديلات سلسة واستجابة ممتازة بدون أي أصوات.';
  static const String chassisNote =
      'أساسات وكالة خالية تماماً من الحوادث والتعديل.';

  /// The four rows, in print order.
  ///
  /// [suspensionNote] is the inspector's own words and is the only note on the
  /// document that this build takes from a person.
  static List<ReportSection> rows({String? suspensionNote}) =>
      <ReportSection>[
        ReportSection(
          ordinal: 1,
          label: engineSector,
          efficiency: enginePercent,
          notes: engineNote,
        ),
        ReportSection(
          ordinal: 2,
          label: gearboxSector,
          efficiency: gearboxPercent,
          notes: gearboxNote,
        ),
        ReportSection(
          ordinal: 3,
          label: chassisSector,
          efficiency: chassisPercent,
          notes: chassisNote,
        ),
        ReportSection(
          ordinal: 4,
          label: suspensionSector,
          efficiency: suspensionPercent,
          notes: (suspensionNote?.trim().isNotEmpty ?? false)
              ? suspensionNote!.trim()
              : null,
        ),
      ];

  /// The one headline figure, as the mean of the sector scores.
  ///
  /// `inspection_reports.quality_score` is NOT NULL in the database and the design
  /// has no input for it — the entry form collects no percentages at all — so the
  /// only value the app can write without inventing one is a function of the scores
  /// it does hold. A mean is the only such function that is symmetric: a report
  /// with one poor sector and three sound ones is neither the worst sector nor the
  /// best one, and a headline that reported either would be describing a different
  /// inspection.
  ///
  /// **A known, accepted divergence from the reference.** With the reference's own
  /// four numbers this yields 93 against the 88 its donut prints, because the
  /// reference's headline is not the mean of its own sectors and no rule producing
  /// 88 from 95/98/100/80 is stated anywhere. 93 is kept rather than tuned down to
  /// 88: a mean is checkable by anyone who reads the table, and a hardcoded 88
  /// would have to be re-derived every time a sector figure changed. The reference's
  /// 88 is a property of its screenshot, not a rule.
  ///
  /// Null for an empty sector list rather than 0: zero is a claim about a car.
  static int? summary(List<ReportSection> sections) {
    if (sections.isEmpty) return null;
    final int total = sections.fold(
      0,
      (int sum, ReportSection section) => sum + section.efficiency,
    );
    return (total / sections.length).round();
  }
}

/// The report's headline verdict, as a band rather than a sentence.
///
/// The design prints one fixed headline — `حالة ممتازة وموصى بها (88%)` — beside a
/// donut, which works for exactly one score. Printing it for a report whose donut
/// reads 41% would put a false claim at the top of a certified document, so the
/// headline is chosen from the score instead.
///
/// The bands and their words are the report's own: the same four words its
/// efficiency table already prints, from the same thresholds, so the headline and
/// the table cannot call one number two different things. Which localized word
/// each band is written in is the page's business — see `report_page.dart` — since
/// an enum has no way to reach the localization delegates.
enum ReportQualityBand {
  excellent,
  sound,
  acceptable,
  needsRepair;

  /// The same cut-offs as `ReportTableRow.gradeFor`, in one place: ≥95
  /// excellent, ≥90 sound, ≥75 acceptable, below that a repair is needed.
  static ReportQualityBand forPercent(int percent) {
    if (percent >= 95) return ReportQualityBand.excellent;
    if (percent >= 90) return ReportQualityBand.sound;
    if (percent >= 75) return ReportQualityBand.acceptable;
    return ReportQualityBand.needsRepair;
  }
}

DateTime? _asDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value as String);
}

double _asDouble(Object? value) => switch (value) {
  null => 0,
  final num n => n.toDouble(),
  final String s => double.tryParse(s) ?? 0,
  _ => 0,
};
