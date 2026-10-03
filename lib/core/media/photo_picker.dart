import 'package:image_picker/image_picker.dart';

/// Opens the device's photo library and hands back what the user chose.
///
/// An interface with one method, for the same reason the rest of this app takes
/// its repositories through providers: every screen with a photo control has to
/// be testable. A widget test cannot open a real gallery, and a form whose photo
/// control can only be driven on a device is a form whose photo control is
/// untested.
///
/// Deliberately one method and no [ImageSource] parameter. The design offers one
/// control — `+ إضافة` — and a gallery rather than a camera because the evidence
/// is of a car the inspector has already stood in front of: the odometer, the
/// engine bay, the corners. A second source would be a control the reference does
/// not draw.
///
/// In `core` rather than inside a feature because two features need it: the
/// report form uploads photos of the car, and the sign-up form uploads the
/// user's ID. Sharing it from either feature would make the other depend on it,
/// which is how an auth screen ends up importing a repository it has no use for.
/// `core` is the only package allowed to sit above both.
abstract class PhotoPicker {
  /// The chosen image, or null if the user dismissed the library.
  Future<XFile?> pickFromGallery();
}

/// The real picker, backed by `image_picker`.
class SystemPhotoPicker implements PhotoPicker {
  const SystemPhotoPicker();

  /// Reused rather than constructed per call: the plugin registers its platform
  /// implementation once, and a new instance per tap buys nothing.
  static final ImagePicker _picker = ImagePicker();

  @override
  Future<XFile?> pickFromGallery() => _picker.pickImage(
    source: ImageSource.gallery,
    // Downscaled, not re-encoded wholesale. The A4 prints a photo 45dp wide and
    // the phone gallery has a 12-megapixel original, so uploading the original
    // would spend a field inspector's mobile data on pixels nobody can see.
    // 2048px is four times the print width at 600dpi, which is as much detail as
    // the page can hold.
    maxWidth: 2048,
    imageQuality: 90,
  );
}