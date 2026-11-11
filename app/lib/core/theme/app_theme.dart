import 'package:flutter/material.dart';

import 'app_tokens.dart';

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent).copyWith(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    // Tonal buttons stay neutral grey so they never compete with the accent CTA.
    secondaryContainer: AppColors.surfaceMuted,
    onSecondaryContainer: AppColors.ink,
    surface: AppColors.background,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkSecondary,
    surfaceContainer: AppColors.surfaceMuted,
    surfaceContainerHighest: AppColors.surfaceMuted,
    outline: AppColors.inkTertiary,
    outlineVariant: AppColors.divider,
    error: AppColors.danger,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
  );

  // Tight letter-spacing on large text keeps headlines punchy;
  // body text keeps default spacing for readability.
  const text = TextTheme(
    displaySmall: TextStyle(
        fontSize: 34, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -0.8),
    headlineMedium: TextStyle(
        fontSize: 28, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.6),
    titleLarge: TextStyle(
        fontSize: 20, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: -0.2),
    titleMedium: TextStyle(fontSize: 16, height: 1.3, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 16, height: 1.45),
    bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: AppColors.inkSecondary),
    labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.inkSecondary),
  );

  const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
        .merge(text),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: AppColors.ink,
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    // Text boxes: white fill, hairline border, a thicker INK border on focus.
    // Focus uses ink rather than the accent, so the accent stays reserved for
    // the main button on each screen.
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: 14),
      border: _outline(AppColors.divider),
      enabledBorder: _outline(AppColors.divider),
      focusedBorder: _outline(AppColors.ink, width: 1.5),
      errorBorder: _outline(AppColors.danger),
      focusedErrorBorder: _outline(AppColors.danger, width: 1.5),
      labelStyle: const TextStyle(color: AppColors.inkSecondary),
      floatingLabelStyle: const TextStyle(color: AppColors.ink),
      helperStyle: const TextStyle(color: AppColors.inkSecondary),
      errorStyle: const TextStyle(color: AppColors.danger),
      helperMaxLines: 2,
      errorMaxLines: 2,
    ),
    // Chips (form, days, times): neutral when off, solid ink when selected —
    // a clear "on" state that still leaves the accent to the Save button.
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.ink : AppColors.surface,
      ),
      labelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.ink,
        ),
      ),
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(
          color: s.contains(WidgetState.selected) ? AppColors.ink : AppColors.divider,
        ),
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
      ),
      iconTheme: const IconThemeData(color: AppColors.inkSecondary, size: 18),
      deleteIconColor: AppColors.inkSecondary,
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.ink,
        selectedBackgroundColor: AppColors.ink,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: AppColors.divider),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
        ),
        minimumSize: const Size(0, 44),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.divider),
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    // Bottom tabs: white bar, neutral pill behind the selected tab.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.surfaceMuted,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? AppColors.ink : AppColors.inkSecondary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? AppColors.ink : AppColors.inkSecondary,
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.divider,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: text.bodyLarge?.copyWith(color: Colors.white),
      actionTextColor: AppColors.accentOnDark,
      insetPadding: const EdgeInsets.fromLTRB(
          AppSpace.screen, 0, AppSpace.screen, AppSpace.lg),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
      ),
      elevation: 0,
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
  );
}

OutlineInputBorder _outline(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(AppRadius.control)),
      borderSide: BorderSide(color: color, width: width),
    );
