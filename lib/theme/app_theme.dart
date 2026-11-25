import 'package:flutter/material.dart';

import 'palettes.dart';
import 'tokens.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light([Palette p = const Palette('Mitti', Mitti.terracotta, Mitti.terracottaLight)]) {
    final sf = Surfaces.of(p, false);
    final scheme = ColorScheme.fromSeed(
      seedColor: p.light,
      brightness: Brightness.light,
    ).copyWith(
      primary: p.light,
      onPrimary: p.onPrimary,
      surface: sf.surface,
      onSurface: sf.text,
      error: Mitti.error,
    );
    return _base(scheme, sf).copyWith(
      scaffoldBackgroundColor: sf.bg,
      dividerColor: sf.line,
      extensions: [BaatlyColors.from(p, sf, false)],
    );
  }

  static ThemeData dark([Palette p = const Palette('Mitti', Mitti.terracotta, Mitti.terracottaLight)]) {
    final sf = Surfaces.of(p, true);
    final scheme = ColorScheme.fromSeed(
      seedColor: p.light,
      brightness: Brightness.dark,
    ).copyWith(
      primary: p.dark,
      onPrimary: p.onPrimary,
      surface: sf.surface,
      onSurface: sf.text,
      error: const Color(0xFFF2B8B5),
    );
    return _base(scheme, sf).copyWith(
      scaffoldBackgroundColor: sf.bg,
      dividerColor: sf.line,
      extensions: [BaatlyColors.from(p, sf, true)],
    );
  }

  static ThemeData _base(ColorScheme scheme, Surfaces sf) {
    final isDark = scheme.brightness == Brightness.dark;
    final text = sf.text;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Poppins',
      brightness: scheme.brightness,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      appBarTheme: AppBarTheme(
        backgroundColor: sf.surface,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? scheme.primary
            : (isDark ? sf.raised : Color.lerp(sf.raised, Colors.black, 0.06)!)),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}

/// Extra brand colours not covered by Material's ColorScheme.
@immutable
class BaatlyColors extends ThemeExtension<BaatlyColors> {
  final Color bg;
  final Color surface;
  final Color raised; // chips, search, incoming bubble on plain bg
  final Color text;
  final Color muted;
  final Color line;
  final Color outBubble;
  final Color onOutBubble;
  final Color inBubble;
  /// Set for gradient themes: paint out-bubbles / send button with it.
  final Gradient? accentGradient;

  const BaatlyColors({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.text,
    required this.muted,
    required this.line,
    required this.outBubble,
    required this.onOutBubble,
    required this.inBubble,
    this.accentGradient,
  });

  factory BaatlyColors.from(Palette p, Surfaces sf, bool dark) => BaatlyColors(
        bg: sf.bg,
        surface: sf.surface,
        raised: sf.raised,
        text: sf.text,
        muted: sf.muted,
        line: sf.line,
        outBubble: p.light,
        onOutBubble: p.onPrimary,
        inBubble: dark ? sf.raised : Colors.white,
        accentGradient: p.linear,
      );

  static const light = BaatlyColors(
    bg: Mitti.cream,
    surface: Colors.white,
    raised: Mitti.sand,
    text: Mitti.ink,
    muted: Mitti.clay,
    line: Mitti.line,
    outBubble: Mitti.terracotta,
    onOutBubble: Colors.white,
    inBubble: Colors.white,
  );

  static const dark = BaatlyColors(
    bg: Mitti.night,
    surface: Mitti.nightSurface,
    raised: Mitti.nightRaised,
    text: Mitti.nightText,
    muted: Mitti.nightMuted,
    line: Mitti.nightLine,
    outBubble: Mitti.terracotta,
    onOutBubble: Colors.white,
    inBubble: Mitti.nightRaised,
  );

  @override
  BaatlyColors copyWith() => this;

  @override
  BaatlyColors lerp(ThemeExtension<BaatlyColors>? other, double t) {
    if (other is! BaatlyColors) return this;
    return t < 0.5 ? this : other;
  }
}

extension BaatlyContext on BuildContext {
  BaatlyColors get bc => Theme.of(this).extension<BaatlyColors>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get primary => Theme.of(this).colorScheme.primary;
}
