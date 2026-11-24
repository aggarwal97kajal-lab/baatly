import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(milliseconds: 2100), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: Mitti.medium,
        pageBuilder: (_, __, ___) => const WelcomeScreen(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = CurvedAnimation(parent: _c, curve: const Interval(0, 0.55, curve: Curves.easeOutBack));
    final fade = CurvedAnimation(parent: _c, curve: const Interval(0.35, 0.85, curve: Curves.easeOut));
    final halo = CurvedAnimation(parent: _c, curve: const Interval(0.2, 1, curve: Curves.easeOut));
    return Scaffold(
      backgroundColor: Mitti.terracotta,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 200,
              height: 200,
              child: Stack(alignment: Alignment.center, children: [
                AnimatedBuilder(
                  animation: halo,
                  builder: (_, __) => Container(
                    width: 120 + 80 * halo.value,
                    height: 120 + 80 * halo.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.10 * (1 - halo.value * 0.6)),
                    ),
                  ),
                ),
                ScaleTransition(scale: scale, child: const BaatlyMark(size: 96, white: true)),
              ]),
            ),
            const SizedBox(height: 8),
            FadeTransition(
              opacity: fade,
              child: const Column(children: [
                Text('BAATLY',
                    style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 5)),
                SizedBox(height: 6),
                Text('Every Conversation Matters',
                    style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 14, letterSpacing: 1)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
