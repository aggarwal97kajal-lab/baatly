import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'intro_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Expanded(
                child: Stack(alignment: Alignment.center, children: [
                  Container(width: 280, height: 280, decoration: BoxDecoration(color: bc.raised, shape: BoxShape.circle)),
                  Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(color: bc.raised.withOpacity(0.9), shape: BoxShape.circle, border: Border.all(color: bc.line, width: 8))),
                  const BaatlyMark(size: 100),
                  const Positioned(left: 0, top: 40, child: _Chip('Namaste!')),
                  const Positioned(right: 0, top: 80, child: _Chip('Kaise ho?', brand: true)),
                  const Positioned(left: 0, bottom: 70, child: _Chip('Ghar kab aaoge?')),
                  const Positioned(right: 10, bottom: 40, child: _Chip('Kal subah!')),
                ]),
              ),
              const SizedBox(height: 16),
              Text('Har baat, apno ke saath.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, color: bc.text)),
              const SizedBox(height: 10),
              Text('Messages, voice notes, calls aur status —\nsab ek jagah, tez aur surakshit.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: bc.muted, height: 1.5)),
              const SizedBox(height: 36),
              FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IntroScreen())),
                child: const Text('Shuru karein'),
              ),
              const SizedBox(height: 18),
              Text.rich(
                TextSpan(
                  text: 'Aage badhkar aap hamari Terms aur Privacy Policy ',
                  children: [TextSpan(text: 'maante hain', style: TextStyle(color: context.primary, fontWeight: FontWeight.w700))],
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: bc.muted),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool brand;
  const _Chip(this.text, {this.brand = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: brand ? context.primary : context.bc.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Text(text, style: TextStyle(fontSize: 13, color: brand ? Colors.white : context.bc.text)),
    );
  }
}
