import 'package:flutter/material.dart';

import 'tokens.dart';

/// One colour theme the user can pick in Settings › Chats › Theme.
/// [light] is the brand colour on light backgrounds (deeper, readable with white text),
/// [dark] the one used on dark backgrounds (a bit brighter).
class Palette {
  final String name;
  final Color light;
  final Color dark;
  final Color onPrimary;
  final List<Color>? gradient;
  const Palette(this.name, this.light, this.dark, {this.onPrimary = Colors.white, this.gradient});

  bool get isGradient => gradient != null;

  /// What to paint a swatch / filled button with.
  Gradient? get linear => gradient == null
      ? null
      : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient!);
}

const palettes = <Palette>[
  Palette('Mitti', Mitti.terracotta, Mitti.terracottaLight),
  Palette('Neem', Color(0xFF1F8A70), Color(0xFF2BA37F)),
  Palette('Neel', Color(0xFF2F5BD3), Color(0xFF4A74E8)),
  Palette('Jamun', Color(0xFF7B4FC9), Color(0xFF9466E0)),
  Palette('Gulabi', Color(0xFFC9446E), Color(0xFFE05C86)),
  Palette('Samundar', Color(0xFF0E8C9B), Color(0xFF14A7B8)),
  Palette('Kesar', Color(0xFFE06C00), Color(0xFFF57C00)),
  Palette('Aam', Color(0xFFC99500), Color(0xFFF2B705), onPrimary: Color(0xFF1A1A1A)),
  Palette('Lal', Color(0xFFC62828), Color(0xFFE53935)),
  Palette('Coffee', Color(0xFF7E4E33), Color(0xFFA0694A)),
  Palette('Pista', Color(0xFF5F8226), Color(0xFF7FA33A)),
  Palette('Aasmaan', Color(0xFF0A84C6), Color(0xFF29A3E0)),
  Palette('Indigo', Color(0xFF4A55C4), Color(0xFF6673E0)),
  Palette('Rani', Color(0xFFA12483), Color(0xFFC2389F)),
  Palette('Sona', Color(0xFFA8821F), Color(0xFFD4A93C), onPrimary: Color(0xFF1A1A1A)),
  Palette('Graphite', Color(0xFF566570), Color(0xFF8A9AA6)),
  Palette('Gulmohar', Color(0xFFE5533D), Color(0xFFFF6F59)),
  Palette('Mehroon', Color(0xFFA3324F), Color(0xFFC2456A)),
  Palette('Lavender', Color(0xFF7C5FD6), Color(0xFFA68BEB)),
  Palette('Mint', Color(0xFF13A57A), Color(0xFF2FCB98)),
  Palette('Chandan', Color(0xFF9C7445), Color(0xFFC9A06E)),
  Palette('Sage', Color(0xFF5E7D66), Color(0xFF8AA892)),
  Palette('Sunset', Color(0xFFE0566E), Color(0xFFFF7E5F), gradient: [Color(0xFFFF7E5F), Color(0xFFD94D8A)]),
  Palette('Ocean', Color(0xFF1F6FD0), Color(0xFF3B8BEB), gradient: [Color(0xFF2F80ED), Color(0xFF14B8A6)]),
  Palette('Aurora', Color(0xFF6A45C4), Color(0xFF8A63D8), gradient: [Color(0xFF7B4FC9), Color(0xFF2F80ED)]),
  Palette('Aam Ras', Color(0xFFE0661A), Color(0xFFF79A2E), gradient: [Color(0xFFF7B733), Color(0xFFFC4A1A)]),
];

/// Current brand colour (light shade) for places without a BuildContext. Kept in sync by AppState.
Color brandColor = Mitti.terracotta;

Palette paletteAt(int i) => palettes[i.clamp(0, palettes.length - 1)];

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// Surface colours for a palette. Mitti keeps its exact hand-picked warm surfaces;
/// every other palette gets neutral surfaces with a faint tint of its own colour.
class Surfaces {
  final Color bg, surface, raised, text, muted, line;
  const Surfaces(this.bg, this.surface, this.raised, this.text, this.muted, this.line);

  static Surfaces of(Palette p, bool dark) {
    if (p.name == 'Mitti') {
      return dark
          ? const Surfaces(Mitti.night, Mitti.nightSurface, Mitti.nightRaised, Mitti.nightText, Mitti.nightMuted, Mitti.nightLine)
          : const Surfaces(Mitti.cream, Colors.white, Mitti.sand, Mitti.ink, Mitti.clay, Mitti.line);
    }
    final c = p.dark;
    if (dark) {
      return Surfaces(
        _mix(const Color(0xFF0F0F10), c, 0.05),
        _mix(const Color(0xFF18181A), c, 0.08),
        _mix(const Color(0xFF222225), c, 0.10),
        const Color(0xFFEDEDED),
        const Color(0xFF9D9D9D),
        _mix(const Color(0xFF2A2A2D), c, 0.06),
      );
    }
    return Surfaces(
      _mix(Colors.white, c, 0.045),
      Colors.white,
      _mix(Colors.white, c, 0.12),
      const Color(0xFF16181A),
      const Color(0xFF6B7176),
      _mix(const Color(0xFFE9E9E9), c, 0.10),
    );
  }
}
