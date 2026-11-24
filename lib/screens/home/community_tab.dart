import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class CommunityTab extends StatelessWidget {
  const CommunityTab({super.key});

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Scaffold(
      backgroundColor: bc.bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.symmetric(horizontal: 24), children: [
          const SizedBox(height: 18),
          Text('Community', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: bc.text)),
          const SizedBox(height: 60),
          Center(
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(color: bc.raised, shape: BoxShape.circle),
              child: Icon(Icons.groups_rounded, size: 84, color: context.primary),
            ),
          ),
          const SizedBox(height: 28),
          Text('Apne mohalle, society ya\nclass ko ek jagah laayein',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: bc.text, height: 1.3)),
          const SizedBox(height: 10),
          Text('Groups ko ek community mein jodein, announcements bhejein aur channels follow karein.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: bc.muted, height: 1.5)),
          const SizedBox(height: 30),
          FilledButton(onPressed: () => showComingSoon(context, 'Communities'), child: const Text('Community banayein')),
          const SizedBox(height: 10),
          Text('Milestone 8 mein aayega', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: bc.muted)),
        ]),
      ),
    );
  }
}
