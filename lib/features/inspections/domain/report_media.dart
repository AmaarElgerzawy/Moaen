/// One attachment on a report — a row of `public.report_media`.
///
/// The column is called `media_url` but holds a *storage object path*, not a URL.
/// `inspection-media` is a private bucket, so every read needs a signed URL and a
/// signed URL expires; storing one would write a dead link into an append-only
/// table, and `report_media` has no UPDATE policy — evidence cannot be rewritten.
/// So [path] is the durable value and [url] is minted per read.
///
/// [url] therefore has a shelf life, and a [ReportMedia] held for longer than
/// [MediaRepository.signedUrlLifetime] will fail to load. Both consumers render
/// through a widget that falls back to its caption on an image error, so an
/// expired URL degrades to "the photo is there" rather than to a broken box on a
/// certified document.
class ReportMedia {
  const ReportMedia({
    required this.id,
    required this.reportId,
    required this.path,
    required this.url,
    this.description,
    this.createdAt,
  });

  final String id;
  final String reportId;

  /// The object path inside the `inspection-media` bucket:
  /// `{inspection_id}/{filename}` — the shape migration 0003's
  /// `storage_inspection_id` parses to decide who may read the object.
  final String path;

  /// A signed URL, valid for `MediaRepository.signedUrlLifetime`.
  final String url;

  /// Free text about what the photo shows. Null today: Screen 5 collects none,
  /// and an invented caption on evidence would be a claim nobody made.
  final String? description;

  final DateTime? createdAt;

  factory ReportMedia.fromRow(
    Map<String, dynamic> row,
    String url,
  ) => ReportMedia(
    id: row['id'] as String,
    reportId: row['report_id'] as String,
    path: row['media_url'] as String,
    url: url,
    description: row['description'] as String?,
    createdAt: row['created_at'] == null
        ? null
        : DateTime.tryParse(row['created_at'] as String),
  );
}