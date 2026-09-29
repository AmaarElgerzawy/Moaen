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

/// The brand palette, from the approved design system.
///
/// These are the colours the Figma screens specify verbatim, so they are
/// constants rather than Material tones: a status chip that is "light green
/// with emerald text" has to be exactly that, and re-deriving it from the
/// scheme would let a seed change shift the whole UI while claiming stability.
///
/// Where a colour is *not* pinned by the design, the theme lets Material 3
/// derive it from the seed as usual — the palette below is the seam, not every
/// pixel.
abstract final class AppColors {
  /// Primary brand: active CTAs, ticked steps, highlighted totals.
  static const Color emerald = Color(0xFF00875A);

  /// Dark slate: app bars and header banners.
  static const Color slate = Color(0xFF0D131A);

  /// Screen background: a soft off-white.
  static const Color canvas = Color(0xFFF4F6F8);

  /// Hairline border on cards.
  static const Color cardBorder = Color(0xFFE5E9EB);

  /// Light green surface — success chips, the estimate box.
  static const Color successSurface = Color(0xFFE6F4EA);

  /// Light amber surface — pending/warning chips and the tracking state.
  static const Color warningSurface = Color(0xFFFEF3D6);

  /// The amber foreground that reads against [warningSurface].
  static const Color warningOn = Color(0xFFD97706);

  /// Light blue surface — informational chips ("assigned").
  static const Color infoSurface = Color(0xFFEAF1FB);

  /// The blue foreground that reads against [infoSurface].
  static const Color infoOn = Color(0xFF1F5AA8);

  /// Neutral grey chip surface for settled/cancelled states.
  static const Color neutralSurface = Color(0xFFEDEFF1);

  /// The grey foreground that reads against [neutralSurface].
  static const Color neutralOn = Color(0xFF5F6B76);
}

/// The application theme.
///
/// Kept deliberately narrow. Material 3 derives most of the component styling
/// from the seed, so overriding a component theme here is a decision that has to
/// be justified by a visible problem, not a preference.
abstract final class AppTheme {
  /// Emerald green (design system). Reads as trustworthy and mechanical rather
  /// than recreational, which suits a product where the buyer is spending real
  /// money on a second-hand car and is nervous about it.
  static const Color seed = AppColors.emerald;

  static ThemeData light() {
    final ColorScheme colors = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(
      // `fromSeed` never lands on the brand colour itself, so the primary is
      // pinned explicitly — an emerald CTA that renders as teal is a spec
      // violation nobody can point at in code.
      primary: AppColors.emerald,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: AppColors.canvas,
      visualDensity: VisualDensity.standard,

      appBarTheme: AppBarTheme(
        centerTitle: true,
        // The dark slate header bar from the design: the same surface every
        // page top sits on, which is what makes the chrome read as one system.
        backgroundColor: AppColors.slate,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        // White cards on the off-white canvas, with a hairline border instead
        // of a shadow: the flat look the design specifies.
        color: Colors.white,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.cardBorder),
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

      // The active tab indicator on the inspector's navigation bar: light
      // emerald surface with the emerald icon, as the design's active states.
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: AppColors.successSurface,
        iconTheme: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.emerald
                : colors.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.emerald
                : colors.onSurfaceVariant,
          ),
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