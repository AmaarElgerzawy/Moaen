import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/inspection_centre.dart';
import '../domain/inspection_report.dart';
import '../domain/inspection_request.dart';
import 'inspection_repository.dart';

/// What the report-entry form has collected, ready to be written.
///
/// A separate type from [InspectionReport] for the same reason
/// `InspectionDraft` is separate from `InspectionRequest`: the form is allowed to
/// be incomplete in ways a row is not, and the difference between them is where
/// "is this sendable" is decided.
///
/// The sector scores are percentages rather than migration 0001's 1..5 ratings
/// because a bar on the A4 report has to be able to show 80% and 100%, and a 0..5
/// score would imply a precision the inspector did not express. Where the design
/// prints its own figure beside a verdict — `ممتاز (95%)` — that figure is the one
/// carried through, so the report shows the number the inspector agreed to rather
/// than a re-derived one.
class ReportDraft {
  const ReportDraft({
    required this.inspectionId,
    required this.conditionScore,
    required this.qualityScore,
    required this.centreInvoiceNo,
    required this.resultSummary,
    required this.sections,
    this.parts = const <ReportPart>[],
    this.obdClean = true,
    this.obdNotes,
    this.repairEstimate,
  });

  final String inspectionId;
  final bool obdClean;
  final String? obdNotes;
  final double? repairEstimate;
  final int conditionScore;
  final int qualityScore;
  final String centreInvoiceNo;
  final String resultSummary;
  final List<ReportSection> sections;

  /// The blueprint chips the A4 draws beside the car outline.
  ///
  /// Defaults to empty rather than being required, because a first issue with no
  /// chips is a valid document: [ReportRepository.replaceParts] deletes the
  /// existing rows and inserts these, so an empty list clears them rather than
  /// leaving the previous draft's verdicts attached to a new inspection.
  final List<ReportPart> parts;

  /// Omitted rather than sent empty, like `InspectionDraft.toRow`: `''` is a
  /// value, and the screens read NULL as "not recorded yet".
  Map<String, dynamic> toRow() => <String, dynamic>{
    'obd_clean': obdClean,
    'repair_estimate': repairEstimate,
    'condition_score': conditionScore,
    'quality_score': qualityScore,
    'center_invoice_no': centreInvoiceNo,
    'result_summary': resultSummary,
    if (obdNotes != null && obdNotes!.trim().isNotEmpty)
      'obd_notes': obdNotes!.trim(),
  };
}

/// All reads and writes of `public.inspection_reports` and its two child tables.
///
/// The report is a document, so the write shape here differs from
/// [InspectionRepository]'s: an upsert of the header row, then the sector rows
/// and blueprint chips, then the issue. A partial document is worse than an
/// absent one — a buyer who can see a half-written report has been told findings
/// exist that have not been made — so [certify] is a separate, deliberate call
/// rather than something [upsert] does implicitly.
class ReportRepository {
  ReportRepository(this._client, this._inspections);

  final SupabaseClient _client;

  /// Reads the inspection row the report belongs to, so the car, plate, city and
  /// reference the report cites come from the same `InspectionRequest` the rest of
  /// the app uses. Passed in rather than reimplemented here: `car_inspections`
  /// has twenty columns of decoding quirks in `fromRow` and duplicating that
  /// would leave two places to fix.
  final InspectionRepository _inspections;

  static const String _table = 'inspection_reports';
  static const String _sections = 'inspection_report_sections';
  static const String _parts = 'inspection_report_parts';
  static const String _centres = 'inspection_centres';

  /// The full report for one inspection, or null if none has been started.
  ///
  /// One method rather than four, so a caller cannot assemble a bundle whose
  /// header, sectors and chips were each fetched at a slightly different moment.
  /// On a document that is about to be certified, that difference is the whole
  /// question.
  Future<ReportBundle?> load(String inspectionId) async {
    try {
      final Map<String, dynamic>? header = await _client
          .from(_table)
          .select()
          .eq('inspection_id', inspectionId)
          .maybeSingle();
      if (header == null) return null;

      final String reportId = header['id'] as String;

      // The two child reads do not depend on each other, so they are issued
      // together. Sequential reads would double the latency of a screen whose
      // whole job is to display a document.
      final List<List<Map<String, dynamic>>> children =
          await Future.wait(<Future<List<Map<String, dynamic>>>>[
        _client
            .from(_sections)
            .select()
            .eq('report_id', reportId)
            .order('ordinal', ascending: true),
        _client
            .from(_parts)
            .select()
            .eq('report_id', reportId)
            .order('ordinal', ascending: true),
      ]);

      final InspectionRequest request = await _inspections.byId(inspectionId);

      return ReportBundle(
        request: request,
        report: InspectionReport.fromRow(header),
        centre: await _centreFor(request),
        sections: children[0].map(ReportSection.fromRow).toList(),
        parts: children[1].map(ReportPart.fromRow).toList(),
      );
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('report load failed', error, stackTrace, {
        'inspection_id': inspectionId,
      });
      throw const InspectionFailure('Could not load the inspection report.');
    }
  }

  /// The booked centre, resolved from `inspection_centres`.
  ///
  /// By name, not by id: `car_inspections` freezes `inspection_center_name` at
  /// booking time and never stored the centre's id, so the name is the only key
  /// both sides have. The two-centres-one-name case is broken by the table's
  /// `unique (name, city)`, and the query adds the request's own city so the
  /// match is exact rather than merely first. Ordering by fee is then redundant
  /// belt-and-braces on a query the unique constraint already makes unambiguous.
  Future<InspectionCentre?> _centreFor(InspectionRequest request) async {
    final String? name = request.inspectionCenterName;
    if (name == null || name.isEmpty) return null;
    final List<Map<String, dynamic>> rows = await _client
        .from(_centres)
        .select()
        .eq('name', name)
        .eq('city', request.city)
        .limit(1);
    return rows.isEmpty ? null : InspectionCentre.fromRow(rows.first);
  }

  /// Creates the report row, or updates the one already there.
  ///
  /// `inspection_id` is UNIQUE, so an inspector who reopens the form after a
  /// failed submit is updating their own draft rather than producing a second
  /// document. The uniqueness is the idempotency; `onConflict` is how this method
  /// states that it knows.
  Future<String> upsert(ReportDraft draft) async {
    try {
      final Map<String, dynamic> row = await _client
          .from(_table)
          .upsert(
            <String, dynamic>{
              ...draft.toRow(),
              'inspection_id': draft.inspectionId,
            },
            onConflict: 'inspection_id',
          )
          .select('id')
          .single();
      return row['id'] as String;
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('report write failed', error, stackTrace);
      throw const InspectionFailure(
        'Could not save the inspection results. Please try again.',
      );
    }
  }

  /// Replaces the report's sector rows with [sections].
  ///
  /// Delete-then-insert rather than an upsert per row, because the set of sectors
  /// is fixed and [ReportSection.ordinal] is what the A4 table orders by: a row
  /// the inspector removed has to disappear, and a per-row upsert would keep it.
  ///
  /// Not atomic on its own, which is why [certify] is a separate call the form
  /// makes only once every write has returned. A report is issued by an explicit
  /// action, never as a side effect of saving.
  Future<void> replaceSections(
    String reportId,
    List<ReportSection> sections,
  ) async {
    try {
      await _client.from(_sections).delete().eq('report_id', reportId);
      if (sections.isEmpty) return;
      await _client.from(_sections).insert(<Map<String, dynamic>>[
        for (final ReportSection section in sections)
          <String, dynamic>{
            'report_id': reportId,
            'ordinal': section.ordinal,
            'label': section.label,
            'efficiency': section.efficiency,
            if (section.notes != null && section.notes!.trim().isNotEmpty)
              'notes': section.notes!.trim(),
          },
      ]);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('report sector write failed', error, stackTrace);
      throw const InspectionFailure(
        'Could not save the technical sector results. Please try again.',
      );
    }
  }

  /// Writes the blueprint chips. The same replace-then-insert shape as the
  /// sectors, for the same reason.
  Future<void> replaceParts(String reportId, List<ReportPart> parts) async {
    try {
      await _client.from(_parts).delete().eq('report_id', reportId);
      if (parts.isEmpty) return;
      await _client.from(_parts).insert(<Map<String, dynamic>>[
        for (final ReportPart part in parts)
          <String, dynamic>{
            'report_id': reportId,
            'ordinal': part.ordinal,
            'part_key': part.partKey,
            'label_en': part.labelEn,
            'label_ar': part.labelAr,
            'verdict': part.verdict,
            'tone': part.tone.wireName,
          },
      ]);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('report blueprint write failed', error, stackTrace);
      throw const InspectionFailure(
        'Could not save the body inspection map. Please try again.',
      );
    }
  }

  /// Stamps the report as issued.
  ///
  /// Separate from [upsert] because issuing is the moment findings stop being a
  /// draft and become a citable document: the buyer's reports tab and the seal on
  /// the A4 both key off it. A timestamp rather than a status column, because there
  /// is no state after issued — a report cannot be withdrawn in this product, and
  /// a second state would be one nothing ever sets.
  Future<void> certify(String reportId) async {
    try {
      await _client
          .from(_table)
          .update(<String, dynamic>{
            'certified_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', reportId)
          .select()
          .single();
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('report certify failed', error, stackTrace, {
        'report_id': reportId,
      });
      throw const InspectionFailure(
        'Could not issue the report. Please try again.',
      );
    }
  }

  /// Every issued report across [inspectionIds], newest first.
  ///
  /// Takes request ids rather than a user id, because `inspection_reports` has no
  /// `client_id`: participation is defined through the inspection and the RLS
  /// policy already checks it. Listing by the requests the caller can already see
  /// is the same query with one fewer join to get wrong — and a wrong join here
  /// would be a report for the wrong car, on a page whose only content is reports.
  Future<List<InspectionReport>> listForInspections(
    List<String> inspectionIds,
  ) async {
    if (inspectionIds.isEmpty) return const <InspectionReport>[];
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(_table)
          .select()
          .inFilter('inspection_id', inspectionIds)
          .not('certified_at', 'is', null)
          .order('certified_at', ascending: false);
      return rows.map(InspectionReport.fromRow).toList();
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('report list failed', error, stackTrace);
      throw const InspectionFailure('Could not load your reports.');
    }
  }
}
