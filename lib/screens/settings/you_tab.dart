import 'package:flutter/material.dart';

import '../../config.dart';
import '../../data/api.dart';
import '../../data/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../onboarding/passkey_setup_screen.dart';
import '../onboarding/splash_screen.dart';
import 'appearance_screen.dart';
import 'wallpaper_screen.dart';

class YouTab extends StatelessWidget {
  const YouTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final name = s.name.isEmpty ? 'You' : s.name;
        final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
        final ini = (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
        return Scaffold(
          backgroundColor: bc.bg,
          body: SafeArea(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 14), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
                child: Text('You', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: bc.text)),
              ),
              _Group(children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  leading: Avatar(initials: ini, colorIndex: 2, size: 56),
                  title: Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  subtitle: Text('${s.username.isEmpty ? '' : '@${s.username} · '}${s.about}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _editProfile(context),
                ),
              ]),
              const SizedBox(height: 12),
              _Group(children: [
                _row(context, Icons.key_rounded, 'Account', trailing: s.phone.isEmpty ? null : s.phone),
                _row(context, Icons.lock_outline_rounded, 'Privacy', onTap: () => _privacy(context)),
                _row(context, Icons.fingerprint_rounded, 'Passkey', trailing: kHasBackend ? 'Create' : 'Not in demo',
                    onTap: kHasBackend
                        ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PasskeySetupScreen(next: const _PopBack())))
                        : null),
                _row(context, Icons.shield_outlined, 'Security'),
                _row(context, Icons.chat_bubble_outline_rounded, 'Chats'),
                _row(context, Icons.notifications_none_rounded, 'Notifications'),
                _row(context, Icons.data_usage_rounded, 'Storage and data'),
                _row(context, Icons.devices_rounded, 'Linked devices'),
                _row(context, Icons.palette_outlined, 'Appearance',
                    trailing: switch (s.themeMode) { ThemeMode.light => 'Light', ThemeMode.dark => 'Dark', _ => 'System' },
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppearanceScreen()))),
                _row(context, Icons.wallpaper_rounded, 'Chat wallpaper',
                    trailing: s.wallpaper.label,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WallpaperScreen()))),
              ]),
              const SizedBox(height: 12),
              _Group(children: [
                _row(context, Icons.help_outline_rounded, 'Help'),
                _row(context, Icons.info_outline_rounded, 'About BAATLY', onTap: () => _about(context)),
                _row(context, Icons.logout_rounded, 'Log out', onTap: () async {
                  await Api.instance.logout();
                  await AppState.instance.resetDemo();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SplashScreen()), (_) => false);
                }),
              ]),
              const SizedBox(height: 18),
              Center(child: Text('BAATLY v0.1.0 · Demo build (Milestone 1)', style: TextStyle(fontSize: 11, color: bc.muted))),
              const SizedBox(height: 24),
            ]),
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, IconData icon, String title, {String? trailing, VoidCallback? onTap}) {
    final bc = context.bc;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(11)),
        child: Icon(icon, size: 20, color: context.primary),
      ),
      title: Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (trailing != null) Text(trailing, style: TextStyle(fontSize: 12.5, color: bc.muted)),
        Icon(Icons.chevron_right_rounded, color: bc.muted),
      ]),
      onTap: onTap ?? () => showComingSoon(context, title),
    );
  }

  void _editProfile(BuildContext context) {
    final s = AppState.instance;
    final name = TextEditingController(text: s.name);
    final about = TextEditingController(text: s.about);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(sheet).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Edit profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(controller: about, maxLength: 140, decoration: const InputDecoration(labelText: 'About')),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () {
              s.toggle(() {
                if (name.text.trim().isNotEmpty) s.name = name.text.trim();
                s.about = about.text.trim();
              });
              Navigator.pop(sheet);
            },
            child: const Text('Save'),
          ),
        ]),
      ),
    );
  }

  void _privacy(BuildContext context) {
    final s = AppState.instance;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => ListenableBuilder(
        listenable: s,
        builder: (_, __) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              title: const Text('Read receipts'),
              subtitle: const Text('If off, you won\'t see others\' receipts either'),
              value: s.readReceipts,
              onChanged: (v) => s.toggle(() => s.readReceipts = v),
            ),
            SwitchListTile(
              title: const Text('App lock (fingerprint)'),
              subtitle: const Text('Real lock arrives in Milestone 9'),
              value: s.appLock,
              onChanged: (v) => s.toggle(() => s.appLock = v),
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }

  void _about(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'BAATLY',
      applicationVersion: '0.1.0 (Milestone 1 demo)',
      applicationIcon: const BaatlyMark(size: 48),
      children: const [
        Text('Every Conversation Matters.\n\nThis is an early build: design, screens, login and passkeys. '
            'Real messaging, encryption and calls arrive in upcoming milestones.'),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: context.bc.surface, borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

/// After creating a passkey from Settings, just go back.
class _PopBack extends StatelessWidget {
  const _PopBack();
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    });
    return const Scaffold(body: SizedBox.shrink());
  }
}
