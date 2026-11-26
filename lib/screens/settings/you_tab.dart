import 'package:flutter/material.dart';
import '../../data/accounts.dart';

import '../../config.dart';
import '../../data/api.dart';
import '../../data/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../onboarding/passkey_setup_screen.dart';
import '../onboarding/splash_screen.dart';
import 'appearance_screen.dart';
import 'privacy_screen.dart';
import '../chat/starred_screen.dart';
import 'profile_photo.dart';
import 'qr_screen.dart';
import 'accounts_ui.dart';
import '../../widgets/photo_viewer.dart';
import 'wallpaper_screen.dart';
import 'more_settings.dart';
import 'chats_settings.dart';

/// Settings (opened from the ⋮ menu on Chats). Same content as the old "You" tab.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => const YouTab(asPage: true);
}

class YouTab extends StatelessWidget {
  final bool asPage;
  const YouTab({super.key, this.asPage = false});

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
              if (asPage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 10, 10),
                  child: Row(children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded, color: bc.text)),
                    const SizedBox(width: 4),
                    Text('Settings', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: bc.text)),
                  ]),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
                  child: Text('You', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: bc.text)),
                ),
              Material(
                color: bc.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: bc.line)),
                child: InkWell(
                  onTap: () => _editProfile(context),
                  child: Stack(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      height: 56,
                      decoration: BoxDecoration(gradient: bc.brand),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(gradient: RadialGradient(center: Alignment(0.7, -1.4), radius: 1.2, colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)])),
                      ),
                    ),
                    const SizedBox(height: 62),
                    ]),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 24,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          GestureDetector(
                            onTap: () => s.myPhoto != null ? PhotoViewerScreen.open(context, s.myPhoto, name) : changeProfilePhoto(context),
                            child: Stack(clipBehavior: Clip.none, children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(color: bc.surface, shape: BoxShape.circle),
                                child: Avatar(initials: ini, colorIndex: 2, size: 72, photo: s.myPhoto),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 2,
                                child: GestureDetector(
                                  onTap: () => changeProfilePhoto(context),
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(gradient: bc.brand, shape: BoxShape.circle, border: Border.all(color: bc.surface, width: 2.5)),
                                    child: const Icon(Icons.photo_camera_rounded, size: 13, color: Colors.white),
                                  ),
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: bc.text)),
                                Text('${s.username.isEmpty ? '' : '@${s.username} · '}${s.about}',
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: bc.muted)),
                              ]),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: RoundIconButton(
                              tooltip: 'QR code',
                              icon: Icons.qr_code_rounded,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QrScreen())),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              if (kHasBackend && Api.instance.loggedIn) ...[
                const _Group(children: [AccountsSection()]),
                const SizedBox(height: 12),
              ],
              _Group(children: [
                _row(context, Icons.key_rounded, 'Account', trailing: s.phone.isEmpty ? null : s.phone, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen()))),
                _row(context, Icons.lock_outline_rounded, 'Privacy', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyScreen()))),
                _row(context, Icons.star_outline_rounded, 'Starred messages',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StarredScreen()))),
                _row(context, Icons.fingerprint_rounded, 'Fingerprint login',
                    trailing: !kHasBackend ? 'Not in demo' : (Api.instance.hasFingerprint ? 'On ✓' : 'Turn on'),
                    onTap: !kHasBackend
                        ? null
                        : Api.instance.hasFingerprint
                            ? () => _passkeyInfo(context)
                            : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PasskeySetupScreen(next: const _PopBack())))),
                _row(context, Icons.shield_outlined, 'Security', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SecurityScreen()))),
                _row(context, Icons.chat_bubble_outline_rounded, 'Chats',
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatsSettingsScreen()))),
                _row(context, Icons.notifications_none_rounded, 'Notifications', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()))),
                _row(context, Icons.data_usage_rounded, 'Storage and data', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StorageDataScreen()))),
                _row(context, Icons.devices_rounded, 'Linked devices', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LinkedDevicesScreen()))),
                _row(context, Icons.palette_outlined, 'Appearance',
                    trailing: switch (s.themeMode) { ThemeMode.light => 'Light', ThemeMode.dark => 'Dark', _ => 'System' },
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppearanceScreen()))),
                _row(context, Icons.wallpaper_rounded, 'Chat wallpaper',
                    trailing: s.wallpaper.label,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WallpaperScreen()))),
              ]),
              const SizedBox(height: 12),
              _Group(children: [
                _row(context, Icons.help_outline_rounded, 'Help', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen()))),
                _row(context, Icons.info_outline_rounded, 'About BAATLY', onTap: () => _about(context)),
                _row(context, Icons.logout_rounded, 'Log out', onTap: () async {
                  await Api.instance.logout();
                  await AppState.instance.resetDemo();
                  if (await Accounts.instance.afterLogout()) return;
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SplashScreen()), (_) => false);
                }),
              ]),
              const SizedBox(height: 18),
              Center(child: Text('BAATLY v0.1.0', style: TextStyle(fontSize: 11, color: bc.muted))),
              const SizedBox(height: 24),
            ]),
          ),
        );
      },
    );
  }

  static const _tileColors = {
    'Account': Color(0xFFE0A23B),
    'Privacy': Color(0xFF3BA37A),
    'Starred messages': Color(0xFFE3B23C),
    'Fingerprint login': Color(0xFF6673E0),
    'Security': Color(0xFF2F8F9D),
    'Chats': Color(0xFF4C8FD9),
    'Notifications': Color(0xFFD2597E),
    'Storage and data': Color(0xFF4AA8B6),
    'Linked devices': Color(0xFF8E6CCB),
    'Appearance': Color(0xFFE08A4E),
    'Chat wallpaper': Color(0xFF3BA37A),
    'Help': Color(0xFF7E8A94),
    'About BAATLY': Color(0xFFC8553D),
    'Log out': Color(0xFFD9534F),
  };

  Widget _row(BuildContext context, IconData icon, String title, {String? trailing, VoidCallback? onTap}) {
    final bc = context.bc;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: IconTile(icon: icon, color: _tileColors[title] ?? context.primary),
      title: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500)),
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
            onPressed: () async {
              final n = name.text.trim().isNotEmpty ? name.text.trim() : s.name;
              if (kHasBackend && Api.instance.loggedIn && s.username.isNotEmpty) {
                try {
                  await Api.instance.updateProfile(name: n, username: s.username, about: about.text.trim());
                } on ApiException catch (e) {
                  if (sheet.mounted) ScaffoldMessenger.of(sheet).showSnackBar(SnackBar(content: Text(e.message)));
                  return;
                }
              }
              s.toggle(() {
                s.name = n;
                s.about = about.text.trim();
              });
              if (sheet.mounted) Navigator.pop(sheet);
            },
            child: const Text('Save'),
          ),
        ]),
      ),
    );
  }

  void _passkeyInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.verified_user_rounded, size: 56, color: Color(0xFF3E7C5A)),
            const SizedBox(height: 12),
            const Text('Fingerprint login is on', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'Next time you open BAATLY after logging out, tap "Log in with fingerprint" — no OTP needed. It works only on this phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: sheet.bc.muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: () => Navigator.pop(sheet), child: const Text('OK')),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                Navigator.pop(sheet);
                try {
                  await Api.instance.disableFingerprint();
                  AppState.instance.setPasskey(false);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fingerprint login turned off')));
                } on ApiException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
              child: const Text("Turn off fingerprint login", style: TextStyle(color: Color(0xFFB3261E))),
            ),
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
  Widget build(BuildContext context) => Material(
        // Material (not Container) so tap highlights are drawn inside the
        // rounded card instead of leaking out at the corners.
        color: context.bc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: context.bc.line)),
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


