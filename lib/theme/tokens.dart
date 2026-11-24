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
  static const night = Color(0xFF17120F);
  static const nightSurface = Color(0xFF211A16);
  static const nightRaised = Color(0xFF2A221D);
  static const nightLine = Color(0xFF2E2621);
  static const nightText = Color(0xFFF5ECE3);
  static const nightMuted = Color(0xFFA39385);

  // Semantic — kept separate from the brand colour on purpose
  static const error = Color(0xFFB3261E);
  static const success = Color(0xFF3E7C5A);
  static const callGreen = Color(0xFF3E9A63);

  static const avatarColors = [
    Color(0xFFE8A87C),
    Color(0xFF85A3C9),
    Color(0xFFC9A0C2),
    Color(0xFF9CC5A1),
    Color(0xFFE6C36A),
    Color(0xFFA7A3D9),
    Color(0xFFE89C9C),
  ];

  // Spacing & radii
  static const r12 = 12.0;
  static const r18 = 18.0;
  static const r24 = 24.0;

  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);
}
