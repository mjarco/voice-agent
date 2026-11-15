import 'package:flutter/material.dart';
import 'package:voice_agent/core/theme/app_colors.dart';
import 'package:voice_agent/core/widgets/aurora_background.dart';

/// Aurora Graphite (off-roadmap S1, 2026-11-15-va-graphite-theme): grey glass
/// with one teal accent, light and dark, set in Sora. The values are those
/// of the research's mockups (docs/research/2026-11-va-visual-style, 14).
///
/// The schemes are written by hand rather than seeded: a seed tints every
/// surface with the accent, while Graphite's surfaces are neutral grey.
abstract final class AppTheme {
  static const fontFamily = 'Sora';

  static const lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF14897B),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFCDEDE8),
    onPrimaryContainer: Color(0xFF0B3F39),
    secondary: Color(0xFF4A4E55),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE2E3E6),
    onSecondaryContainer: Color(0xFF17191C),
    tertiary: Color(0xFF2FB8A6),
    onTertiary: Color(0xFF04201C),
    tertiaryContainer: Color(0xFFD9F3EF),
    onTertiaryContainer: Color(0xFF0B3F39),
    error: Color(0xFFC62828),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFADBD8),
    onErrorContainer: Color(0xFF5F1111),
    surface: Color(0xFFF2F2F3),
    onSurface: Color(0xFF17191C),
    onSurfaceVariant: Color(0xFF5A5D63),
    surfaceDim: Color(0xFFDCDDE1),
    surfaceBright: Color(0xFFFAFAFB),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F7F8),
    surfaceContainer: Color(0xFFEDEDEF),
    surfaceContainerHigh: Color(0xFFE6E7E9),
    surfaceContainerHighest: Color(0xFFDFE0E3),
    outline: Color(0xFF8A8E95),
    outlineVariant: Color(0xFFD2D5DA),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2A2C31),
    onInverseSurface: Color(0xFFECEEF0),
    inversePrimary: Color(0xFF5FD0C0),
    surfaceTint: Color(0x00000000),
  );

  static const darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF2FB8A6),
    onPrimary: Color(0xFF04201C),
    primaryContainer: Color(0xFF1F6F66),
    onPrimaryContainer: Color(0xFFCFF3EE),
    secondary: Color(0xFFA9ADB4),
    onSecondary: Color(0xFF17191C),
    secondaryContainer: Color(0xFF2E3036),
    onSecondaryContainer: Color(0xFFECEEF0),
    tertiary: Color(0xFF5FD0C0),
    onTertiary: Color(0xFF04201C),
    tertiaryContainer: Color(0xFF184F49),
    onTertiaryContainer: Color(0xFFCFF3EE),
    error: Color(0xFFF2716B),
    onError: Color(0xFF2B0606),
    errorContainer: Color(0xFF5A1A17),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF0D0E10),
    onSurface: Color(0xFFECEEF0),
    onSurfaceVariant: Color(0xFFA3A6AC),
    surfaceDim: Color(0xFF0D0E10),
    surfaceBright: Color(0xFF2E3036),
    surfaceContainerLowest: Color(0xFF08090A),
    surfaceContainerLow: Color(0xFF15161A),
    surfaceContainer: Color(0xFF1A1B1F),
    surfaceContainerHigh: Color(0xFF212328),
    surfaceContainerHighest: Color(0xFF2A2C31),
    outline: Color(0xFF6B6F77),
    outlineVariant: Color(0xFF3A3D44),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFECEEF0),
    onInverseSurface: Color(0xFF17191C),
    inversePrimary: Color(0xFF14897B),
    surfaceTint: Color(0x00000000),
  );

  static ThemeData light() => _build(lightScheme, AppColors.light);
  static ThemeData dark() => _build(darkScheme, AppColors.dark);

  static ThemeData _build(ColorScheme scheme, AppColors colors) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      // The sky is drawn behind every page by its route (S2), so a page's
      // scaffold is clear; the transition carries page and sky together.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: colors.background,
      extensions: [colors],
    );
    final glassFill = Color.alphaBlend(colors.glassFill, colors.background.withValues(alpha: 0.22));
    return base.copyWith(
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        for (final e in const PageTransitionsTheme().builders.entries)
          e.key: AuroraPageTransitionsBuilder(e.value),
      }),
      // A Material card on the sky reads as glass until its screen is
      // restyled (S3, S4).
      cardTheme: CardThemeData(
        color: glassFill,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colors.glassLine),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      // S3: Material's own parts on glass, so every screen's chips,
      // switches, check boxes, sheets and fields share Aurora's shapes.
      listTileTheme: const ListTileThemeData(tileColor: Colors.transparent),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        shape: Border(),
        collapsedShape: Border(),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colors.chip,
        selectedColor: scheme.onSurface,
        secondarySelectedColor: scheme.onSurface,
        checkmarkColor: scheme.surface,
        side: BorderSide(color: colors.glassLine),
        shape: const StadiumBorder(),
        labelStyle: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.onSurface : glassFill,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? scheme.surface : scheme.onSurface,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: colors.glassLine)),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        side: BorderSide(color: scheme.outline, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.onSurface,
        foregroundColor: scheme.surface,
        elevation: 2,
        shape: const CircleBorder(),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glassFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colors.glassLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: colors.glassLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
