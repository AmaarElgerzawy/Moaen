import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/logging/app_logger.dart';

/// Reads and writes identity documents — the ID or residence card a buyer or an
/// inspector uploads at sign-up.
///
/// Separate from `MediaRepository`, and not because the code is unrelated but
/// because the *audience* is. `inspection-media` is readable by both parties to an
/// inspection; migration 0011's `identity-documents` bucket is readable by the
/// account that owns the document and by an admin reviewing it, and by nobody
/// else. An identity document is the most sensitive thing this app holds — it is a
/// government ID — so it does not share a bucket, a path convention or a policy
/// with a photograph of a car's odometer.
///
/// ## Why the upload happens after sign-up
///
/// Supabase Auth mints the user id itself, so there is no id to file an object
/// under until `signUp` has returned. Two consequences, both handled here:
///
///   * the object path is `{user_id}/id.{ext}`, which the bucket's policies read
///     as the ownership check;
///   * [AuthRepository.signUp] therefore signs up first, uploads second, and
///     points `users.id_photo_url` at the result. An account can therefore exist
///     for a moment with no document on file. For a buyer that is harmless — they
///     may use the platform immediately anyway. For an inspector it is *also*
///     harmless, because an unapproved inspector can do nothing, so the admin's
///     queue just shows the row without a photograph until the upload lands, and
///     `UserProfile.isAwaitingDocuments` is what finds those.
///
/// The alternative — asking for the photo as base64 in Auth metadata — would put a
/// government ID inside a JWT, which is replicated into every session and readable
/// by anything holding the token. Not a trade worth making for the sake of
/// ordering.
class IdentityRepository {
  IdentityRepository(this._client);

  final SupabaseClient _client;

  static const String _table = 'users';

  /// The private bucket from migration 0011.
  ///
  /// Named here rather than inlined so the path convention and the policies that
  /// enforce it live in one place, as they do for `inspection-media`.
  static const String bucket = 'identity-documents';

  /// How long a minted URL stays valid.
  ///
  /// An hour, matching `MediaRepository`. Shorter than a session would be better in
  /// principle, but this URL is shown in one screen that is opened and dismissed,
  /// and a shorter lifetime would mean a photo that fails to load if the user looks
  /// at the queue and then comes back to it.
  static const Duration signedUrlLifetime = Duration(hours: 1);

  /// The object path for [userId]'s document.
  ///
  /// Deterministic — `id.jpg` or `id.png` — rather than a timestamped name, so a
  /// re-upload *replaces* the previous document. Two documents for one account is
  /// not a state the product has, and a random name would leave the old object
  /// orphaned in a bucket no client may delete from.
  ///
  /// Pure and static, taking the clock and the source name as parameters, so the
  /// naming rule is testable without an upload.
  static String objectPathFor(String userId, String sourceName) {
    final int dot = sourceName.lastIndexOf('.');
    final String extension = dot == -1
        ? ''
        : sourceName.substring(dot).toLowerCase();
    return '$userId/id${_keptExtensions.contains(extension) ? extension : '.jpg'}';
  }

  /// Extensions kept as-is. Anything else is stored as `.jpg`: the object is served
  /// back with the content type recorded at upload, and a document that will not
  /// render is worse than one whose bytes were re-encoded.
  static const Set<String> _keptExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.heic',
  };

  /// The content type stored alongside the object at [path].
  ///
  /// Recorded explicitly, for the same reason `MediaRepository` records it: without
  /// it Storage serves the document as `application/octet-stream` and neither a
  /// browser nor `Image.network` will render it.
  static String contentTypeFor(String path) {
    final int dot = path.lastIndexOf('.');
    return switch (dot == -1 ? '' : path.substring(dot)) {
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.heic' => 'image/heic',
      _ => 'image/jpeg',
    };
  }

  /// Uploads [file] as [userId]'s document and returns the object path.
  ///
  /// Returns a path rather than a URL, because the bucket is private and a signed
  /// URL written into `users.id_photo_url` would expire and leave the column
  /// pointing at nothing. See [signedIdPhotoUrl] for the read side.
  ///
  /// `upsert: true` so a re-upload replaces rather than failing on the unique
  /// path — a second attempt after a failed one must not be blocked by the first
  /// having half-succeeded.
  ///
  /// Throws [IdentityFailure] on any failure. Unlike the proof photograph, this
  /// upload is not attached to a report that must stay readable, so degrading
  /// quietly is not on the table: an account with no document on file is one an
  /// admin cannot review, and the caller needs to know that.
  Future<String> uploadIdPhoto({
    required String userId,
    required XFile file,
  }) async {
    final String path = objectPathFor(userId, file.name);
    try {
      final Uint8List bytes = await file.readAsBytes();
      await _client.storage.from(bucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: contentTypeFor(path),
          upsert: true,
        ),
      );
      return path;
    } on Object catch (error, stackTrace) {
      AppLogger.instance.error('id photo upload failed', error, stackTrace, {
        'user_id': userId,
        'path': path,
      });
      throw const IdentityFailure('Could not upload your ID photo.');
    }
  }

  /// Points `users.id_photo_url` at [path].
  ///
  /// A separate write from the upload rather than one combined call, because the
  /// column and the object are two facts: an object with no column pointing at it is
  /// invisible to an admin, and a column pointing at an object that never uploaded
  /// is a profile that looks verified and cannot be reviewed. Writing the column
  /// only after the upload returns is what keeps the second state from occurring.
  ///
  /// Ranged to the one row and guarded by the id, so it cannot write over another
  /// account's document even if the caller passes the wrong id — the bucket policy
  /// has already stopped the object being written anywhere else, and
  /// `protect_verification_flags` refuses a client writing anyone else's path.
  Future<void> setIdPhotoPath(String userId, String path) async {
    try {
      await _client
          .from(_table)
          .update(<String, dynamic>{'id_photo_url': path})
          .eq('id', userId);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.instance.error('id photo path write failed', error, stackTrace, {
        'user_id': userId,
      });
      throw const IdentityFailure('Could not save your ID photo.');
    }
  }

  /// A URL for the document at [path] that works for the next hour.
  ///
  /// Empty rather than throwing, for the same reason `MediaRepository`'s
  /// `signedProofUrl` degrades: the admin's verification queue lists inspectors,
  /// and one whose photograph cannot be loaded must not take the whole queue down
  /// with it. The row still renders, with the photo missing and the account still
  /// approvable — an admin who cannot see a document has a way to react to that
  /// which a blank screen does not give them.
  Future<String> signedIdPhotoUrl(String path) async {
    if (path.isEmpty) return '';
    try {
      return await _client.storage
          .from(bucket)
          .createSignedUrl(path, signedUrlLifetime.inSeconds);
    } on Object {
      AppLogger.instance.error(
        'id photo sign failed',
        null,
        StackTrace.current,
        {'path': path},
      );
      return '';
    }
  }

  /// The signed URL for a profile's document, or empty when it has none.
  ///
  /// Takes the profile rather than a path so a caller cannot accidentally sign an
  /// object that does not belong to the account it is displaying.
  Future<String> signedUrlFor(String userId, String? path) async {
    if (path == null || path.isEmpty) return '';
    // Belt and braces against a path that does not start with this account's own
    // id — for instance a column hand-edited in the Supabase dashboard. The
    // bucket policy would refuse to sign it anyway; this turns that into an empty
    // string rather than an exception.
    if (!path.startsWith('$userId/')) return '';
    return signedIdPhotoUrl(path);
  }
}

/// Why an identity document could not be stored.
///
/// A type rather than a message so this class stays free of user-facing English,
/// the way `AuthRepository` does — the words are resolved by the presentation
/// layer from the ARB files, which is what keeps an Arabic build from showing an
/// English sentence in exactly one place.
class IdentityFailure implements Exception {
  const IdentityFailure(this.message);

  /// English, and only ever logged. `AuthRepository` sets the precedent: the reason
  /// is the value, and the localisation table is what turns it into a sentence.
  final String message;

  @override
  String toString() => 'IdentityFailure: $message';
}