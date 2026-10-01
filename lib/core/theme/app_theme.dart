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

  /// 12dp. Between a group and its neighbour, inside a card. Also the design's
  /// gap between sibling cards in a body, and between the choices of a
  /// segmented control.
  static const double md = 12;

  /// 14dp. The design's card padding *and* its page inset — `.card` and `.body`
  /// are both 14 in the reference, so one token covers both rather than two that
  /// happen to agree today.
  ///
  /// Named for what it is rather than slotted into the geometric scale: this is
  /// the one figure the design pins between [md] and [lg], and calling it `md`
  /// or `lg` would be a rounding of something exact.
  static const double inset = 14;

  /// 16dp. The default gap between form fields and list rows.
  static const double lg = 16;

  /// 10dp. The design's two-up field gap and its label's top margin.
  static const double row = 10;

  /// 20dp. Card padding.
  static const double xl = 20;

  /// 24dp. Between distinct sections.
  static const double xxl = 24;

  /// 32dp. Above a heading, below a hero.
  static const double xxxl = 32;
}

abstract final class AppRadius {
  /// 8dp. The report's blueprint chips and its QR placeholder.
  static const double small = 8;

  static const double sm = 8;

  /// Inputs: 12dp. Also the report's photo slots.
  static const double md = 12;

  /// 10dp. The report's four-up data tiles and its attachment slots.
  static const double tile = 10;

  /// Buttons: 14dp.
  static const double button = 14;

  static const double lg = 16;

  /// Cards: 18dp. The design allows 16–20; 18 is the midpoint and is used
  /// wherever the design says "16–20px radius".
  static const double card = 18;

  /// The design's explicitly larger card: the market's request card and the
  /// inspector's task card, both 20dp.
  static const double cardLarge = 20;

  /// The dark header's bottom corners.
  static const double header = 28;

  /// The report's page corners: 4dp, because it is a sheet of paper and not a
  /// screen.
  static const double page = 4;

  /// 30dp. The report's car-outline diagram, which is a rounded capsule.
  static const double car = 30;

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
  /// the market screen's city pill). `#0E3B2C`.
  static const Color darkBadge = Color(0xFF0E3B2C);

  /// The light-green text that sits on [darkBadge]. `#4ADE80`.
  static const Color darkBadgeOn = Color(0xFF4ADE80);

  /// The mint used where the design wants *more* light than the brand green on
  /// a dark surface: the report banner's verdict headline, and the inspector's
  /// "available for work" pill. `#34D399`.
  static const Color mint = Color(0xFF34D399);

  /// The white-on-dark action pill that sits on the buyer's home ("اطلب الآن")
  /// and on the inspector's board cards ("قبول الطلب"). `#F8FAFC`.
  static const Color actionChip = Color(0xFFF8FAFC);

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
  /// note, the booking CTA's softer green. `#E58A00`.
  static const Color warning = Color(0xFFE58A00);

  /// The pale-orange fill behind a warning badge — the "determined later" chip
  /// and the report's flagged blueprint region. `#FFF1DB`.
  static const Color warningSurface = Color(0xFFFFF1DB);

  /// The green the inspector's booking CTA uses: present enough to read as the
  /// same brand, soft enough not to shout over the yellow notice box it sits in.
  /// `#3F9D6A`.
  static const Color greenSoft = Color(0xFF3F9D6A);

  /// The WhatsApp pill's fill and its text. `#86EFAC` / `#14532D`.
  static const Color whatsappFill = Color(0xFF86EFAC);
  static const Color whatsappOn = Color(0xFF14532D);

  /// Red: the "live" dot and text. `#E5484D`.
  static const Color live = Color(0xFFE5484D);

  /// The market's request card border. A cooler gray than [cardBorder] — the
  /// design draws these cards as listings rather than as forms. `#CFE0F3`.
  static const Color marketBorder = Color(0xFFCFE0F3);

  /// Muted body ink on a dark surface: the report banner's paragraph, the
  /// greeting's small line under the name. `#CBD5E1`.
  static const Color onDarkSoft = Color(0xFFCBD5E1);

  /// The photo slot's fill — a flat placeholder for an image nobody has
  /// uploaded yet. `#DDE5EE`.
  static const Color photoFill = Color(0xFFDDE5EE);

  /// The invoice box and the report's attachment slots: a hair off white, so a
  /// box inside a white card still reads as its own surface. `#FAFBFD`.
  static const Color surfaceSunken = Color(0xFFFAFBFD);

  /// The report's car-outline stroke. `#475569`.
  static const Color blueprintOutline = Color(0xFF475569);

  /// The report's glass fill inside that outline. `#B7EBD0`.
  static const Color blueprintGlass = Color(0xFFB7EBD0);

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

  /// The design's very light card shadow — `0 1px 2px rgba(15,23,42,.04)`. It is
  /// there because the design has it, and it is near enough invisible that the
  /// card's border does the real work of separating a card from the canvas.
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x0A0F172A),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// The design's primary button: 50dp tall, 14dp corners, 14sp bold.
  ///
  /// Every height in the design is its own number — the default CTA is 50, the
  /// booking and report buttons are 56 — so the tall variant below is a named
  /// style rather than a per-call-site `minimumSize`.
  static const double buttonHeight = 50;

  /// The taller CTA the design uses where the action is the whole screen: the
  /// inspector's booking confirmation and the report's issue button.
  static const double buttonHeightTall = 56;

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
        hintStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
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
        // The design puts its labels *above* the field, on their own line
        // (`.lbl`), rather than floating inside it. `FieldLabel` renders that
        // line; this is left at `never` so a `TextFormField` cannot also float
        // one inside the box and say the same thing twice.
        floatingLabelBehavior: FloatingLabelBehavior.never,
        // `.fld` is 48dp tall with 14dp of side padding and 13sp type. A
        // `constraints` floor rather than a `contentPadding` tall enough to
        // reach 48 on its own, so a *multiline* field — the notes textarea, the
        // OBD findings box — grows from that same 48 rather than from 48 plus a
        // double row's padding.
        constraints: const BoxConstraints(minHeight: 48),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.inset,
          vertical: AppSpacing.md,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          textStyle: const TextStyle(
            fontSize: 14,
            height: 1.3,
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

      // The design's bottom navigation is text-only: no icons anywhere. Material's
      // `NavigationBar` requires an icon per destination, so both bars in the
      // design are `AppBottomNav` instead — which leaves this theme entry with
      // nothing to style, and it is deliberately absent.

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

  /// The design's black button — "الموافقة على العرض وتأكيد الطلب", "🤝 قبول
  /// الطلب وبدء التنسيق".
  ///
  /// A `FilledButton` with this style rather than a raw `ColoredBox`, so the
  /// ripple, the disabled state and the press feedback come for free while the
  /// 14dp radius and 50dp height the design specifies are kept.
  static ButtonStyle get blackButton => FilledButton.styleFrom(
    backgroundColor: AppColors.darkSurface,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(buttonHeight),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    textStyle: const TextStyle(
      fontSize: 14,
      height: 1.3,
      fontWeight: FontWeight.w700,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    ),
  );

  /// The design's tall CTA: "تأكيد الحجز وإرسال تفاصيل الموعد والمركز" and
  /// "📄 اعتماد وإصدار التقرير النهائي A4". 56dp, and at 15sp because the design
  /// gives these two the largest button type in the product — they are the
  /// screens' only action.
  static ButtonStyle get tallButton => FilledButton.styleFrom(
    backgroundColor: AppColors.green,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(buttonHeightTall),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    textStyle: const TextStyle(
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w700,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    ),
  );

  /// The booking CTA specifically: tall, but in the design's softer green.
  ///
  /// It sits inside the yellow notice box on the inspector's task card, and the
  /// full-strength brand green against that cream reads as an alarm. The design
  /// uses a third green here and this is that third green.
  static ButtonStyle get bookingButton => FilledButton.styleFrom(
    backgroundColor: AppColors.greenSoft,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(buttonHeightTall),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    textStyle: const TextStyle(
      fontSize: 14,
      height: 1.3,
      fontWeight: FontWeight.w700,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
    ),
  );
}

/// The design's type roles, as ready-made [TextStyle]s.
///
/// Titles are bold, secondary text is regular, small and gray, pills are small
/// and bold, and the report adds a tracked wordmark and a roomy body. Anything
/// else on a screen is one of these at a different size, which is what keeps six
/// screens looking like one product.
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
    Color? background,
    FontWeight? weight,
  }) => TextStyle(
    fontSize: size,
    height: 1.2,
    fontWeight: weight ?? FontWeight.w700,
    color: color ?? AppColors.greenDeep,
    backgroundColor: background,
  );

  /// The report's wordmark: `MOAAYEN CERTIFIED`, tracked out at a quarter of an
  /// em and in the brand green.
  ///
  /// Tracking is proportional to the size rather than a flat number, because
  /// the design expresses it as `.25em` — at 10sp that is 2.5 logical pixels,
  /// and hard-coding 2.5 would make the style wrong the moment it is reused at
  /// another size.
  static TextStyle wordmark(double size, {Color? color}) => TextStyle(
    fontSize: size,
    height: 1.2,
    letterSpacing: size * 0.25,
    fontWeight: FontWeight.w700,
    color: color ?? AppColors.green,
  );

  /// The A4 report's body: 12sp on the dark banner, 10sp in its footer. The
  /// design sets these with explicit line heights because the report is dense
  /// and the Arabic needs the room.
  static TextStyle reportBody(double size, {Color color = AppColors.onDarkSoft}) =>
      TextStyle(
        fontSize: size,
        height: 1.8,
        fontWeight: FontWeight.w400,
        color: color,
      );
}
