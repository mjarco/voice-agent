import 'package:flutter/material.dart';

/// Colours by meaning, beside Material's [ColorScheme]: what the scheme has
/// no slot for (a warning that is not an error, the mic's states, the glass
/// and the background of Aurora Graphite). Off-roadmap S1
/// (2026-11-15-va-graphite-theme): the 58 colours set by hand in widgets
/// were moved here or onto the scheme, so a palette is one block of values.
///
/// Read it with [AppColors.of]; a widget pumped without the app's theme
/// (most widget tests) gets the palette of its brightness.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.micRecording,
    required this.micListening,
    required this.micProcessing,
    required this.micIdle,
    required this.micStandby,
    required this.micUnavailable,
    required this.onMic,
    required this.glassFill,
    required this.glassLine,
    required this.chip,
    required this.background,
    required this.blobs,
    required this.accentGradient,
  });

  /// Done, sent, saved: the accent's teal (Graphite has one accent).
  final Color success;
  final Color onSuccess;

  /// Overdue, pending, skipped: orange, never red (red is an error).
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  /// The mic's meanings stay as the owner reads them (research source
  /// 2026-11-15-va-current-theme): red captures, amber listens, grey
  /// processes, teal waits for a tap; slate when paused by the owner.
  final Color micRecording;
  final Color micListening;
  final Color micProcessing;
  final Color micIdle;
  final Color micStandby;
  final Color micUnavailable;

  /// The icon on a mic colour.
  final Color onMic;

  /// The frosted card's fill and its hairline (S2).
  final Color glassFill;
  final Color glassLine;

  /// A pill or chip on glass (times, counts).
  final Color chip;

  /// The page under the glass and the four blobs drifting over it (S2).
  final Color background;
  final List<Color> blobs;

  /// The accent's two stops: the mic orb, the progress bar.
  final List<Color> accentGradient;

  static const light = AppColors(
    success: Color(0xFF14897B),
    onSuccess: Color(0xFFFFFFFF),
    warning: Color(0xFFC2410C),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFBE3D6),
    onWarningContainer: Color(0xFF6A2306),
    micRecording: Color(0xFFDC3B3B),
    micListening: Color(0xFFE08A0B),
    micProcessing: Color(0xFF8A8E95),
    micIdle: Color(0xFF14897B),
    micStandby: Color(0xFF5B6573),
    micUnavailable: Color(0xFFB8BBC1),
    onMic: Color(0xFFFFFFFF),
    glassFill: Color(0x8CFFFFFF),
    glassLine: Color(0xE6FFFFFF),
    chip: Color(0xBFFFFFFF),
    background: Color(0xFFF2F2F3),
    blobs: [Color(0xFFD2D5DA), Color(0xFFE2E3E6), Color(0xFFC5C9CF), Color(0xFFA9E2D9)],
    accentGradient: [Color(0xFF14897B), Color(0xFF2FB8A6)],
  );

  static const dark = AppColors(
    success: Color(0xFF2FB8A6),
    onSuccess: Color(0xFF04201C),
    warning: Color(0xFFFF9D5C),
    onWarning: Color(0xFF2B1204),
    warningContainer: Color(0xFF4A2410),
    onWarningContainer: Color(0xFFFFD9C2),
    micRecording: Color(0xFFF0585B),
    micListening: Color(0xFFF2A93B),
    micProcessing: Color(0xFF6B6F77),
    // Darker than the accent: the white mic needs 3:1 on it.
    micIdle: Color(0xFF1E9C8C),
    micStandby: Color(0xFF7C8592),
    micUnavailable: Color(0xFF3A3D44),
    onMic: Color(0xFFFFFFFF),
    glassFill: Color(0x0FFFFFFF),
    glassLine: Color(0x21FFFFFF),
    chip: Color(0x1AFFFFFF),
    background: Color(0xFF0D0E10),
    blobs: [Color(0xFF3A3D44), Color(0xFF5B5F68), Color(0xFF2A2C31), Color(0xFF1F6F66)],
    accentGradient: [Color(0xFF2FB8A6), Color(0xFF5FD0C0)],
  );

  /// The theme's colours, or the palette of the context's brightness.
  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? micRecording,
    Color? micListening,
    Color? micProcessing,
    Color? micIdle,
    Color? micStandby,
    Color? micUnavailable,
    Color? onMic,
    Color? glassFill,
    Color? glassLine,
    Color? chip,
    Color? background,
    List<Color>? blobs,
    List<Color>? accentGradient,
  }) =>
      AppColors(
        success: success ?? this.success,
        onSuccess: onSuccess ?? this.onSuccess,
        warning: warning ?? this.warning,
        onWarning: onWarning ?? this.onWarning,
        warningContainer: warningContainer ?? this.warningContainer,
        onWarningContainer: onWarningContainer ?? this.onWarningContainer,
        micRecording: micRecording ?? this.micRecording,
        micListening: micListening ?? this.micListening,
        micProcessing: micProcessing ?? this.micProcessing,
        micIdle: micIdle ?? this.micIdle,
        micStandby: micStandby ?? this.micStandby,
        micUnavailable: micUnavailable ?? this.micUnavailable,
        onMic: onMic ?? this.onMic,
        glassFill: glassFill ?? this.glassFill,
        glassLine: glassLine ?? this.glassLine,
        chip: chip ?? this.chip,
        background: background ?? this.background,
        blobs: blobs ?? this.blobs,
        accentGradient: accentGradient ?? this.accentGradient,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<Color> l(List<Color> a, List<Color> b) =>
        [for (var i = 0; i < a.length && i < b.length; i++) c(a[i], b[i])];
    return AppColors(
      success: c(success, other.success),
      onSuccess: c(onSuccess, other.onSuccess),
      warning: c(warning, other.warning),
      onWarning: c(onWarning, other.onWarning),
      warningContainer: c(warningContainer, other.warningContainer),
      onWarningContainer: c(onWarningContainer, other.onWarningContainer),
      micRecording: c(micRecording, other.micRecording),
      micListening: c(micListening, other.micListening),
      micProcessing: c(micProcessing, other.micProcessing),
      micIdle: c(micIdle, other.micIdle),
      micStandby: c(micStandby, other.micStandby),
      micUnavailable: c(micUnavailable, other.micUnavailable),
      onMic: c(onMic, other.onMic),
      glassFill: c(glassFill, other.glassFill),
      glassLine: c(glassLine, other.glassLine),
      chip: c(chip, other.chip),
      background: c(background, other.background),
      blobs: l(blobs, other.blobs),
      accentGradient: l(accentGradient, other.accentGradient),
    );
  }
}
