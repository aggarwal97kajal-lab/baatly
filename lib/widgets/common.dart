import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class Avatar extends StatelessWidget {
  final String initials;
  final int colorIndex;
  final double size;
  final bool online;
  const Avatar({super.key, required this.initials, required this.colorIndex, this.size = 50, this.online = false});

  @override
  Widget build(BuildContext context) {
    final c = Mitti.avatarColors[colorIndex % Mitti.avatarColors.length];
    // Material ancestor so the Hero flight never renders debug text styling.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.34,
                fontFamily: 'Poppins',
                decoration: TextDecoration.none,
              ),
            ),
          ),
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  color: context.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.bc.bg, width: 2.5),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

class BaatlyMark extends StatelessWidget {
  final double size;
  final bool white;
  const BaatlyMark({super.key, this.size = 32, this.white = false});

  @override
  Widget build(BuildContext context) {
    final asset = white
        ? 'assets/brand/mark_white.png'
        : (context.isDark ? 'assets/brand/mark_light.png' : 'assets/brand/mark_terracotta.png');
    return Image.asset(asset, width: size, height: size, filterQuality: FilterQuality.high);
  }
}

/// Read-tick blues: one for light backgrounds (chat list), one for the
/// terracotta outgoing bubble where a darker blue would disappear.
const kReadBlue = Color(0xFF1E88E5);
const kReadBlueOnBubble = Color(0xFF9FDCFF);

class Ticks extends StatelessWidget {
  final MsgStatus status;
  final Color color;
  final Color readColor;
  const Ticks({super.key, required this.status, required this.color, this.readColor = kReadBlue});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MsgStatus.sending:
        return Icon(Icons.schedule_rounded, size: 13, color: color.withOpacity(0.8));
      case MsgStatus.sent:
        return Icon(Icons.done_rounded, size: 15, color: color.withOpacity(0.85));
      case MsgStatus.delivered:
        return Icon(Icons.done_all_rounded, size: 15, color: color.withOpacity(0.7));
      case MsgStatus.read:
        if (!AppState.instance.readReceipts) {
          return Icon(Icons.done_all_rounded, size: 15, color: color.withOpacity(0.7));
        }
        return Icon(Icons.done_all_rounded, size: 15, color: readColor);
    }
  }
}

/// Animated three-dot typing indicator.
class TypingDots extends StatefulWidget {
  final Color color;
  const TypingDots({super.key, required this.color});
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = (_c.value * 3 - i).clamp(0.0, 1.0);
          final y = math.sin(t * math.pi) * -4;
          return Transform.translate(
            offset: Offset(0, y),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: widget.color.withOpacity(0.4 + 0.6 * math.sin(t * math.pi)), shape: BoxShape.circle),
            ),
          );
        }),
      ),
    );
  }
}

/// Static waveform used for voice notes.
class VoiceWave extends StatelessWidget {
  final Color color;
  final double progress;
  const VoiceWave({super.key, required this.color, this.progress = 0.35});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: Row(
        children: List.generate(26, (i) {
          final h = 6 + 18 * (math.sin(i * 0.9) * math.cos(i * 0.37)).abs();
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.2),
            width: 3,
            height: h,
            decoration: BoxDecoration(
              color: color.withOpacity(i / 26 < progress ? 1 : 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

/// Chat background: Mitti dots, a doodle image, or plain.
class ChatBackground extends StatelessWidget {
  final Widget child;
  const ChatBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final w = AppState.instance.wallpaper;
    final dark = context.isDark;
    Widget bg;
    String? asset = w.asset;
    if (dark && asset != null && w != Wallpaper.raat) asset = Wallpaper.raat.asset;
    if (asset != null) {
      bg = Image.asset(asset, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    } else if (w == Wallpaper.mittiDots) {
      bg = CustomPaint(painter: _DotsPainter(context.primary.withOpacity(dark ? 0.10 : 0.16)), child: const SizedBox.expand());
    } else {
      bg = const SizedBox.expand();
    }
    return Container(
      color: dark ? Mitti.night : const Color(0xFFF7EFE5),
      child: Stack(children: [Positioned.fill(child: bg), Positioned.fill(child: child)]),
    );
  }
}

class _DotsPainter extends CustomPainter {
  final Color color;
  _DotsPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (double x = 11; x < size.width; x += 22) {
      for (double y = 11; y < size.height; y += 22) {
        canvas.drawCircle(Offset(x, y), 1.6, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.color != color;
}

/// A tappable pill used in lists of options.
class Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const Pill({super.key, required this.label, this.selected = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Mitti.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? context.primary : context.bc.raised,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : context.bc.text,
          ),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: context.bc.muted)),
      );
}

void showComingSoon(BuildContext context, String what) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('$what — agle milestone mein aayega'),
      duration: const Duration(seconds: 2),
    ));
}
