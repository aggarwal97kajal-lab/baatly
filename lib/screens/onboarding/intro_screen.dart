import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'phone_screen.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pc = PageController();
  int _page = 0;

  static const _pages = [
    (Icons.forum_rounded, 'Har baat, turant.', 'Messages, photos aur voice notes —\nnetwork kamzor ho tab bhi.'),
    (Icons.lock_rounded, 'Aapki baat, sirf aapki.', 'Personal chats end-to-end encrypted\nhongi. (Encryption agle milestone\nmein judega.)'),
    (Icons.videocam_rounded, 'Aamne-saamne baat.', 'Audio aur video calls — akele ya\npoore parivaar ke saath.'),
  ];

  void _next() {
    if (_page == _pages.length - 1) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PhoneScreen()));
    } else {
      _pc.nextPage(duration: Mitti.medium, curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PhoneScreen())),
              child: Text('Skip', style: TextStyle(color: bc.muted, fontWeight: FontWeight.w700)),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final p = _pages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(color: bc.raised, shape: BoxShape.circle),
                      child: Icon(p.$1, size: 96, color: context.primary),
                    ),
                    const SizedBox(height: 40),
                    Text(p.$2, textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: bc.text)),
                    const SizedBox(height: 12),
                    Text(p.$3, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.5, color: bc.muted)),
                  ]),
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pages.length, (i) {
              final on = i == _page;
              return AnimatedContainer(
                duration: Mitti.fast,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: on ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(color: on ? context.primary : bc.line, borderRadius: BorderRadius.circular(4)),
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: FilledButton(onPressed: _next, child: Text(_page == _pages.length - 1 ? 'Shuru karein' : 'Aage')),
          ),
        ]),
      ),
    );
  }
}
