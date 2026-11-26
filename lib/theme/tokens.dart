import 'package:flutter/material.dart';

/// BAATLY "Mitti" design tokens.
class Mitti {
  Mitti._();

  // Brand
  static const terracotta = Color(0xFFC8553D);
  static const terracottaLight = Color(0xFFE0694F); // accent on dark backgrounds

  // Light surfaces
  static const cream = Color(0xFFFBF6EF);
  static const sand = Color(0xFFF1E7DB);
  static const line = Color(0xFFEDE3D7);
  static const ink = Color(0xFF2A211C);
  static const clay = Color(0xFF8A7B70);

  // Dark surfaces
  static const night = Color(0xFF120E0C);
  static const nightSurface = Color(0xFF1C1613);
  static const nightRaised = Color(0xFF251D19);
  static const nightLine = Color(0xFF2A221E);
  static const nightText = Color(0xFFF5ECE3);
  static const nightMuted = Color(0xFFA39385);

  // Semantic — kept separate from the brand colour on purpose
  static const error = Color(0xFFB3261E);
  static const success = Color(0xFF3E7C5A);
  static const callGreen = Color(0xFF3E9A63);

  static const avatarColors = [
    Color(0xFFE08A4E),
    Color(0xFF4C8FD9),
    Color(0xFF8E6CCB),
    Color(0xFF3BA37A),
    Color(0xFFD9A43A),
    Color(0xFF6673E0),
    Color(0xFFD2597E),
  ];

  /// Deeper end of each avatar gradient.
  static const avatarDeep = [
    Color(0xFFC0632B),
    Color(0xFF2F6CB8),
    Color(0xFF6B4BA8),
    Color(0xFF22805A),
    Color(0xFFB0801F),
    Color(0xFF4A55C4),
    Color(0xFFB03A60),
  ];

  // Spacing & radii
  static const r12 = 12.0;
  static const r18 = 18.0;
  static const r24 = 24.0;

  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);
}
