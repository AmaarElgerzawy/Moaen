import 'package:flutter/material.dart';

/// Design tokens for Moaen (معاين).
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

  /// 16dp. The default gap between form fields and list rows. The design's
  /// screen-edge padding.
  static const double lg = 16;

  /// 20dp. Card padding.
  static const double xl = 20;

  /// 24dp. Between distinct sections.
  static const double xxl = 24;

  /// 32dp. Above a heading, below a hero.
  static const double xxxl = 32;
}

abstract final class AppRadius {
  static const double sm = 8;

  /// Inputs: 12dp.
  static const double md = 12;

  /// Buttons: 14dp.
  static const double button = 14;

  static const double lg = 16;

  /// Cards: 16dp. The design allows 16–20; 18 is the midpoint and is used
  /// wherever the design says "16–20px radius".
  static const double card = 18;

  /// The design's explicitly larger card (the new-request card, 20dp).
  static const double cardLarge = 20;

  /// The dark header's bottom corners.
  static const double header = 28;

  /// Full rounding, for pills, avatars and chips.
  static const double pill = 999;
}

/// The brand palette, sampled from the approved design system.
///
/// These are the colours the design specifies, so they are constants rather than
/// Material tones: a status chip that is "light green with dark green text" has
/// to be exactly that, and re-deriving it from the scheme would let a seed change
/// shift the whole UI while claiming stability.
///
/// Where a colour is *not* pinned by the design, the theme lets Material 3 derive
/// it from the seed as usual — the palette below is the seam, not every pixel.
abstract final class AppColors {
  // ---- Dark surfaces -------------------------------------------------------

  /// Dark header background: the top of every screen. `#0B1220`.
  static const Color darkHeader = Color(0xFF0B1220);

  /// The lighter end of the dark range, and the black buttons' fill. `#0F172A`.
  static const Color darkSurface = Color(0xFF0F172A);

  /// The square icon button that sits *on* a dark header. `#1E293B`.
  static const Color darkSquare = Color(0xFF1E293B);

  /// The dark-green badge on a dark header (the inspector's verified badge,
  /// the market screen's city pill).
  static const Color darkBadge = Color(0xFF0B3B2A);

  /// The light-green text that sits on [darkBadge].
  static const Color darkBadgeOn = Color(0xFF7DDFAE);

  // ---- Brand green ---------------------------------------------------------

  /// Primary green: active CTAs, ticked steps, highlighted totals. `#16A05F`.
  static const Color green = Color(0xFF16A05F);

  /// The gradient's dark end, and dark-green bold text on a light-green
  /// surface. `#0E7A4A`.
  static const Color greenDeep = Color(0xFF0E7A4A);

  /// The green gradient of the new-request card: `#16A05F` → `#0E7A4A`.
  static const LinearGradient greenGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[green, greenDeep],
  );

  // ---- Light surfaces ------------------------------------------------------

  /// Light green fill, used by the success pills and the cost-structure card.
  /// `#E8F8F0`.
  static const Color successSurface = Color(0xFFE8F8F0);

  /// The border that pairs with [successSurface]. `#A7E3C4`.
  static const Color successBorder = Color(0xFFA7E3C4);

  /// Page background. `#F8FAFC`.
  static const Color canvas = Color(0xFFF8FAFC);

  /// Cards and the screens' white surfaces.
  static const Color surface = Color(0xFFFFFFFF);

  /// Input fill. `#F1F5F9`.
  static const Color inputFill = Color(0xFFF1F5F9);

  /// The hairline border on cards, inputs and the light-gray info strips.
  /// `#E2E8F0`.
  static const Color cardBorder = Color(0xFFE2E8F0);

  /// The dashed dividers, which need to be visible enough to read as a rule.
  static const Color dashed = Color(0xFFCBD5E1);

  // ---- Text ----------------------------------------------------------------

  /// Primary text. `#0F172A`.
  static const Color textPrimary = Color(0xFF0F172A);

  /// Secondary text: the small gray subtitles under every title. `#64748B`.
  static const Color textSecondary = Color(0xFF64748B);

  /// Muted text on a dark header ("مرحباً بك", the subtitle lines).
  static const Color onDarkMuted = Color(0xFF94A3B8);

  // ---- Semantic ------------------------------------------------------------

  /// The yellow notice box fill. `#FFF8E1`.
  static const Color alertSurface = Color(0xFFFFF8E1);

  /// The yellow notice box's border. `#F3D77A`.
  static const Color alertBorder = Color(0xFFF3D77A);

  /// The brown text on [alertSurface]. `#7A3E0A`.
  static const Color alertOn = Color(0xFF7A3E0A);

  /// Orange: the warning chip, the "80%" efficiency row, the cosmetic-paint
  /// note. The design applies it at 80% opacity for decorative paint only.
  static const Color warning = Color(0xFFE58A00);

  /// Red: the "live" dot and text. `#E5484D`.
  static const Color live = Color(0xFFE5484D);

  /// The donut progress track on the dark report banner.
  static const Color donutTrack = Color(0xFF334155);
}

/// The application theme.
///
/// Kept deliberately narrow. Material 3 derives most of the component styling
/// from the seed, so overriding a component theme here is a decision that has to
/// be justified by a visible problem, not a preference.
abstract final class AppTheme {
  /// The brand green. Reads as trustworthy and mechanical rather than
  /// recreational, which suits a product where the buyer is spending real money
  /// on a second-hand car and is nervous about it.
  static const Color seed = AppColors.green;

  /// The design's very light card shadow — present, but only just. The card
  /// border does the real work of separating a card from the canvas.
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x0D0F172A),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static ThemeData light() {
    final ColorScheme colors = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(
      // `fromSeed` never lands on the brand colour itself, so the primary is
      // pinned explicitly — a green CTA that renders as teal is a spec
      // violation nobody can point at in code.
      primary: AppColors.green,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: AppColors.canvas,
      visualDensity: VisualDensity.standard,

      appBarTheme: AppBarTheme(
        centerTitle: true,
        // The dark header bar from the design: the same surface every page top
        // sits on, which is what makes the chrome read as one system.
        backgroundColor: AppColors.darkHeader,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // The design's input fill is a light gray, not white — a filled field has
        // to read as recessed without needing a shadow.
        fillColor: AppColors.inputFill,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
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
          borderSide: const BorderSide(color: AppColors.green, width: 2),
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
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppColors.cardBorder),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      // The design's bottom navigation is text-only: no icons anywhere, which
      // is why the destinations below are built as a custom bar rather than
      // Material's `NavigationBar` (which requires an icon per destination).
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: AppColors.successSurface,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 13,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.green
                : AppColors.textSecondary,
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
        color: AppColors.cardBorder,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    );
  }

  /// The design's black button — "الموافقة على العرض وتأكيد الطلب", "قبول الطلب
  /// وبدء التنسيق", "اتصال".
  ///
  /// A `FilledButton` with this style rather than a raw `ColoredBox`, so the
  /// ripple, the disabled state and the press feedback come for free while the
  /// 14dp radius and 48dp height the design specifies are kept.
  static ButtonStyle get blackButton => FilledButton.styleFrom(
    backgroundColor: AppColors.darkSurface,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(48),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    ),
  );
}

/// The design's two type roles, as ready-made [TextStyle]s.
///
/// The design names exactly two: titles are bold, secondary text is regular,
/// small and gray. Anything else on a screen is one of these two at a different
/// size, which is what keeps six screens looking like one product.
abstract final class AppText {
  /// A screen or card title. Bold, near-black.
  static TextStyle title(double size, {Color? color, FontWeight? weight}) =>
      TextStyle(
        fontSize: size,
        height: 1.35,
        fontWeight: weight ?? FontWeight.w700,
        color: color ?? AppColors.textPrimary,
      );

  /// The small gray line under a title.
  static TextStyle secondary(
    double size, {
    Color? color,
    FontWeight? weight,
  }) => TextStyle(
    fontSize: size,
    height: 1.4,
    fontWeight: weight ?? FontWeight.w400,
    color: color ?? AppColors.textSecondary,
  );

  /// Bold white text on a dark header.
  static TextStyle onDark(double size, {FontWeight? weight}) => TextStyle(
    fontSize: size,
    height: 1.3,
    fontWeight: weight ?? FontWeight.w700,
    color: Colors.white,
  );

  /// A pill or badge: small, bold, fully rounded.
  static TextStyle pill(
    double size, {
    Color? color,
    FontWeight? weight,
  }) => TextStyle(
    fontSize: size,
    height: 1.2,
    fontWeight: weight ?? FontWeight.w700,
    color: color ?? AppColors.greenDeep,
  );
}
