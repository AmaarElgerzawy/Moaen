import 'package:flutter/material.dart';

/// Design tokens for Moaen.
///
/// Every screen reads its spacing, radius and colour from here rather than
/// hard-coding numbers. Two reasons, in order of importance:
///
///  * When a design arrives, or a decision is revisited, one file changes rather
///    than forty call sites. Screens written against tokens can be re-skinned by
///    editing tokens; screens written against literals cannot.
///  * Literal drift is invisible. `EdgeInsets.all(16)` on one screen and
///    `EdgeInsets.all(15)` on the next looks like two deliberate choices in a diff
///    and one accident to anyone reading the UI.
///
/// The scales are geometric rather than arbitrary so that a value can be chosen
/// by intent — "this is a small gap" — instead of by taste.
abstract final class AppSpacing {
  /// 4dp. Hairline separation, icon-to-label.
  static const double xs = 4;

  /// 8dp. Between related items: a label and its field.
  static const double sm = 8;

  /// 12dp. Between a group and its neighbour, inside a card.
  static const double md = 12;

  /// 16dp. The default gap between form fields and list rows.
  static const double lg = 16;

  /// 24dp. Screen edge padding, and between distinct sections.
  static const double xl = 24;

  /// 32dp. Above a heading, below a hero.
  static const double xxl = 32;

  /// 48dp. Above a page title.
  static const double xxxl = 48;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;

  /// Cards and sheets.
  static const double card = 16;

  /// Full rounding, for pills, avatars and chips.
  static const double pill = 999;
}

/// The application theme.
///
/// Kept deliberately narrow. Material 3 derives most of the component styling
/// from the seed, so overriding a component theme here is a decision that has to
/// be justified by a visible problem, not a preference.
abstract final class AppTheme {
  /// Deep green. Reads as trustworthy and mechanical rather than recreational,
  /// which suits a product where the buyer is spending real money on a
  /// second-hand car and is nervous about it.
  static const Color seed = Color(0xFF0E6B55);

  static ThemeData light() {
    final ColorScheme colors = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      visualDensity: VisualDensity.standard,

      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colors.error),
        ),
        // Arabic labels sit inside the field. Left-aligned and vertically centred
        // reads correctly in both directions; `floatingLabelBehavior` is left at
        // the default so a label that overlaps a filled field cannot happen.
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
      ),

      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: colors.outlineVariant,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }
}
