import 'package:flutter/material.dart';

/// Design tokens. Every colour, gap and corner radius in the app comes from
/// here, so the whole UI stays consistent and easy to change in one place.
abstract final class AppColors {
  // Neutrals — warm off-white background with near-black ink for strong contrast.
  static const background = Color(0xFFF7F7F5);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFEDEEEA);
  static const ink = Color(0xFF111418); // 17.8 : 1 on background
  static const inkSecondary = Color(0xFF545A65); // 6.6 : 1 on background
  static const inkTertiary = Color(0xFF8A909B); // decorative / disabled only
  static const divider = Color(0xFFE2E3DF);

  /// The ONE accent colour. Used only for the primary action on a screen
  /// and for a few key highlights (progress bar, streak flame).
  static const accent = Color(0xFF0B7A5E); // 5.4 : 1 on white
  static const onAccent = Color(0xFFFFFFFF);

  /// Lighter tint of the same accent, for text on the dark snack bar.
  static const accentOnDark = Color(0xFF7FD9BE);

  /// Semantic colour, not an accent: only used to flag a missed dose.
  static const danger = Color(0xFFB42318);
}

abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const section = 40.0;

  /// Left and right margin of every screen.
  static const screen = 20.0;
}

abstract final class AppRadius {
  /// Outer radius of a card.
  static const card = 24.0;

  /// Padding inside a card.
  static const cardPadding = AppSpace.lg;

  /// Inner radius = outer radius − padding (24 − 16 = 8).
  /// Anything sitting inside a card (buttons, thumbnails) uses this value so
  /// its corners run parallel to the card's corners instead of clipping.
  static const cardInner = card - cardPadding;

  /// Buttons outside cards use the same value, so every button matches.
  static const control = cardInner;

  static const bone = 6.0; // skeleton placeholder blocks
  static const full = 999.0;
}

/// Tabular figures make every digit the same width, so times like 08:00 and
/// 11:11 line up in a column and counters don't wobble when they change.
extension TabularFigures on TextStyle {
  TextStyle get tabular =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
