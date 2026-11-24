import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../home/home_shell.dart';

/// UI only in Milestone 1 — real Android permission prompts are wired in later
/// milestones, when the features that need them (contacts, calls) exist.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool contacts = true, notifs = true, mic = false;

  void _go() => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeShell()), (_) => false);

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    Widget card(IconData icon, String title, String body, bool v, ValueChanged<bool> on) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: bc.surface, borderRadius: BorderRadius.circular(20)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: context.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: bc.text)),
                const SizedBox(height: 4),
                Text(body, style: TextStyle(fontSize: 12, color: bc.muted, height: 1.4)),
              ]),
            ),
            Switch(value: v, onChanged: on),
          ]),
        );
    return Scaffold(
      backgroundColor: bc.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            const SizedBox(height: 40),
            Text('A few permissions', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: bc.text)),
            const SizedBox(height: 8),
            Text('You can change these anytime in Settings.', style: TextStyle(fontSize: 13, color: bc.muted)),
            const SizedBox(height: 24),
            card(Icons.person_rounded, 'Contacts', 'To find friends on BAATLY. Your address book isn\'t stored on our servers.',
                contacts, (v) => setState(() => contacts = v)),
            card(Icons.notifications_rounded, 'Notifications', 'For new messages and incoming calls.', notifs,
                (v) => setState(() => notifs = v)),
            card(Icons.mic_rounded, 'Microphone & camera', 'For voice notes and calls. We\'ll ask the first time you use them.', mic,
                (v) => setState(() => mic = v)),
            const SizedBox(height: 24),
            FilledButton(onPressed: _go, child: const Text('Continue')),
            TextButton(
              onPressed: _go,
              child: Text('Later', style: TextStyle(color: context.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
