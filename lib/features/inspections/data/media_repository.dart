import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/report_media.dart';
import 'inspection_repository.dart';

/// Reads and writes `public.report_media`, and the `inspection-media` objects the
/// rows point at.
///
/// Separate from [ReportRepository] because this is a different lifetime: a
/// report's findings are written once and certified, whereas a photo is picked
/// while the inspector is still standing in front of the car and uploaded the
/// moment the document is issued. Splitting them also keeps `image_picker` out of
/// the report repository, which has no reason to know what a gallery is.
///
/// Append-only, because the database says so: migration 0002 grants
/// `select, insert` and nothing else on `report_media`, and migration 0003 grants
/// an INSERT-only policy on the bucket. There is therefore no [remove], and the
/// entry form cannot offer to delete a photo that is already attached to a
/// report — a report's evidence trail has to be stable, which is the whole reason
/// the policy exists.
class MediaRepository {
  MediaRepository(this._client);

  final SupabaseClient _client;

  static const String _table = 'report_media';

  /// The private bucket from migration 0003. Named here rather than inlined so
  /// the path convention and the bucket that enforces it live in one place.
  static const String bucket = 'inspection-media';

  /// How long a minted URL stays valid.
  ///
  /// An hour is longer than any screen in this app stays open, so a report cannot
  /// expire its own images by being left in the background. It is not longer than
  /// that because a URL that outlives its need is a bearer token for the object,
  /// and these photos are readable by the buyer.
  static const Duration signedUrlLifetime = Duration(hours: 1);

  /// Extensions kept as-is when an uploaded object is named. Anything else is
  /// stored as `.jpg`: the object is served back with the content type recorded
  /// at upload, and a photo the inspector cannot open is worse than one whose
  /// bytes were re-encoded.
  static const Set<String> _keptExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
  };

  /// Every photo attached to one report, in the order they were attached.
  ///
  /// Ordering is by `created_at` rather than by the picker order the report was
  /// issued in: `report_media` has no ordinal column, and a timestamp is the only
  /// record of sequence the table keeps.
  Future<List<ReportMedia>> listForReport(String reportId) async {
    if (reportId.isEmpty) return const <ReportMedia>[];
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from(_table)
          .select()
          .eq('report_id', reportId)
          .order('created_at', ascending: true);

      final List<ReportMedia> media = await Future.wait(<Future<ReportMedia>>[
        for (final Map<String, dynamic> row in rows)
          _withSignedUrl(row),
      ]);
      return media;
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('report media list failed', error, stackTrace, {
        'report_id': reportId,
      });
      throw const InspectionFailure('Could not load the inspection photos.');
    }
  }

  /// One row plus a URL that works for the next hour.
  Future<ReportMedia> _withSignedUrl(Map<String, dynamic> row) async {
    final String path = row['media_url'] as String;
    try {
      final String url = await _client.storage
          .from(bucket)
          .createSignedUrl(path, signedUrlLifetime.inSeconds);
      return ReportMedia.fromRow(row, url);
    } on Object {
      // One photo whose URL could not be minted must not lose the whole report
      // to the client: the row is real, the object is real, and the consumer
      // falls back to its caption when the image fails. An empty URL is that
      // fallback, stated once here rather than at three call sites.
      AppLogger.instance.error(
        'report media sign failed',
        null,
        StackTrace.current,
        {'path': path},
      );
      return ReportMedia.fromRow(row, '');
    }
  }

  /// Uploads [files] and attaches them to [reportId], in order.
  ///
  /// Sequential rather than concurrent on purpose. `created_at` is the only thing
  /// recording which photo came first, so the upload order has to match the order
  /// the inspector picked them in, and a concurrent upload would let the network
  /// decide the order of a certified document's evidence.
  ///
  /// Fails on the first file that does not upload, leaving the ones already
  /// attached in place. That is deliberate and not a rollback concern: they are
  /// real photos of a real car, the table is append-only so nothing can remove
  /// them, and the inspector's next attempt adds the rest. The alternative —
  /// collecting all the bytes first and writing only once everything succeeded —
  /// would mean holding every photo of an inspection in memory at once.
  Future<List<ReportMedia>> attachAll({
    required String inspectionId,
    required String reportId,
    required List<XFile> files,
  }) async {
    final List<ReportMedia> attached = <ReportMedia>[];
    for (final XFile file in files) {
      attached.add(
        await attach(
          inspectionId: inspectionId,
          reportId: reportId,
          file: file,
        ),
      );
    }
    return attached;
  }

  /// One photo: the bytes go to the bucket, then the row that points at them.
  ///
  /// Object first, row second. A row whose object is missing would be a caption on
  /// nothing, and the storage bucket's orphan cleanup is what removes the reverse
  /// case — an object nothing points at yet — not this method.
  Future<ReportMedia> attach({
    required String inspectionId,
    required String reportId,
    required XFile file,
  }) async {
    final String path = '$inspectionId/${objectNameFor(file.name)}';
    try {
      final Uint8List bytes = await file.readAsBytes();
      await _client.storage.from(bucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: contentTypeFor(path),
          // Never overwrite. Two photos taken in the same millisecond would share
          // a name, and an inspection's evidence is not something to replace.
          upsert: false,
        ),
      );

      final Map<String, dynamic> row = await _client
          .from(_table)
          .insert(<String, dynamic>{
            'report_id': reportId,
            'media_url': path,
            'media_type': 'image',
          })
          .select()
          .single();

      return await _withSignedUrl(row);
    } on Object catch (error, stackTrace) {
      AppLogger.instance.error('report media upload failed', error, stackTrace, {
        'inspection_id': inspectionId,
        'report_id': reportId,
      });
      throw const InspectionFailure(
        'Could not attach a photo to the report. Please try again.',
      );
    }
  }

  /// The object's file name, for a file the picker called [sourceName].
  ///
  /// Derived from the clock rather than taken from [XFile.name], because the
  /// picker's name is the source app's own (`image_picker1745….jpg` on Android, a
  /// `IMG-` prefix on iOS) and it says nothing useful six months later. What does
  /// matter is that it is unique within the inspection, which the millisecond
  /// stamp guarantees and a content hash would not need to.
  ///
  /// Static and takes the clock as a parameter so the naming rule is one pure
  /// function rather than something that can only be observed by uploading a file
  /// and reading the bucket back.
  ///
  /// The name is also the only part of the object path the storage policy does not
  /// read — its first segment must be the inspection id — so it must never contain
  /// a separator.
  static String objectNameFor(
    String sourceName, {
    DateTime? at,
  }) {
    final int dot = sourceName.lastIndexOf('.');
    final String extension = dot == -1
        ? ''
        : sourceName.substring(dot).toLowerCase();
    final String stamp = (at ?? DateTime.now())
        .toUtc()
        .millisecondsSinceEpoch
        .toString();
    return '$stamp${_keptExtensions.contains(extension) ? extension : '.jpg'}';
  }

  /// The content type stored alongside the object at [path].
  ///
  /// Recorded explicitly because the file name no longer carries the source app's
  /// extension convention: without it Storage would serve every photo as
  /// `application/octet-stream`, which both a browser and `Image.network` refuse to
  /// render.
  static String contentTypeFor(String path) {
    final int dot = path.lastIndexOf('.');
    return switch (dot == -1 ? '' : path.substring(dot)) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.heic' => 'image/heic',
      _ => 'image/jpeg',
    };
  }
}