import 'package:image_picker/image_picker.dart';
import 'package:moaen/features/inspections/data/media_repository.dart';
import 'package:moaen/features/inspections/data/photo_picker.dart';
import 'package:moaen/features/inspections/data/report_repository.dart';
import 'package:moaen/features/inspections/domain/inspection_report.dart';
import 'package:moaen/features/inspections/domain/inspection_request.dart';
import 'package:moaen/features/inspections/domain/report_media.dart';

import 'fake_inspection_repository.dart';
import 'test_client.dart';

/// A [PhotoPicker] that hands back a fixed answer instead of a gallery.
///
/// Two queues rather than one value, because the difference between "the inspector
/// added a photo" and "the inspector dismissed the picker" is the whole subject of
/// two of these tests, and a single field cannot express a sequence.
class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker({List<XFile?>? answers})
    : _answers = List<XFile?>.of(answers ?? <XFile?>[]);

  final List<XFile?> _answers;

  int calls = 0;

  @override
  Future<XFile?> pickFromGallery() async {
    calls++;
    return _answers.isEmpty ? null : _answers.removeAt(0);
  }
}

/// A [MediaRepository] with no storage behind it.
///
/// Records the uploads instead of performing them, and refuses to invent one: the
/// tests assert on the *order* the issue performed its writes in, which is the
/// thing a wrong ordering gets wrong.
class FakeMediaRepository extends MediaRepository {
  FakeMediaRepository({List<ReportMedia>? media})
    : _media = List<ReportMedia>.of(media ?? <ReportMedia>[]),
      super(createTestClient());

  final List<ReportMedia> _media;

  /// Every attachment call, in order: inspection id, report id, file names.
  final List<String> attachedFor = <String>[];
  final List<List<String>> attachedNames = <List<String>>[];

  /// When set, [attachAll] throws it — the shape a phone with no signal produces.
  Object? attachFailure;

  @override
  Future<List<ReportMedia>> listForReport(String reportId) async {
    final Object? failure = attachFailure;
    if (failure != null) throw failure;
    return List<ReportMedia>.of(_media);
  }

  @override
  Future<List<ReportMedia>> attachAll({
    required String inspectionId,
    required String reportId,
    required List<XFile> files,
  }) async {
    final Object? failure = attachFailure;
    if (failure != null) throw failure;
    attachedFor.add('$inspectionId/$reportId');
    attachedNames.add(<String>[
      for (final XFile file in files) file.name,
    ]);
    return const <ReportMedia>[];
  }
}

/// A [ReportRepository] with no network behind it.
///
/// Records the write order, because [ReportController.issue]'s ordering is the
/// behaviour under test: a report that certifies before its photos are attached is
/// a document that says it has no evidence.
class FakeReportRepository extends ReportRepository {
  FakeReportRepository({this.bundle})
    : super(createTestClient(), FakeInspectionRepository());

  /// The bundle [load] returns. Null renders the entry form's "unavailable" state,
  /// which is itself worth a test.
  ReportBundle? bundle;

  Object? failure;

  /// Every write, in the order `issue` performed it.
  final List<String> writes = <String>[];

  static const String reportId = 'report-1';

  @override
  Future<ReportBundle?> load(String inspectionId) async {
    final Object? f = failure;
    if (f != null) throw f;
    return bundle;
  }

  @override
  Future<String> upsert(ReportDraft draft) async {
    final Object? f = failure;
    if (f != null) throw f;
    writes.add('upsert');
    return reportId;
  }

  @override
  Future<void> replaceSections(String reportId, List<ReportSection> sections) async {
    writes.add('sections');
  }

  @override
  Future<void> replaceParts(String reportId, List<ReportPart> parts) async {
    writes.add('parts');
  }

  @override
  Future<void> certify(String reportId) async {
    final Object? f = failure;
    if (f != null) throw f;
    writes.add('certify');
  }

  @override
  Future<List<InspectionReport>> listForInspections(List<String> ids) async =>
      const <InspectionReport>[];
}

/// The report bundle the entry form loads, for [FakeReportRepository].
ReportBundle testReportBundle({InspectionRequest? request}) => ReportBundle(
  request: request ?? buildRequest(id: 'job-1', status: InspectionStatus.inProgress),
  report: const InspectionReport(
    id: FakeReportRepository.reportId,
    inspectionId: 'job-1',
    conditionScore: 93,
    qualityScore: 93,
    centerInvoiceNo: 'INV-1',
    resultSummary: '',
  ),
);