import '../../data/secure_screen.dart';
import 'package:flutter/material.dart';

import 'two_step.dart';

import '../../config.dart';
import '../../data/api.dart';
import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../theme/app_theme.dart';
import '../home/status_privacy_screen.dart';

/// WhatsApp-style privacy settings. The server enforces them, so someone who
/// isn't allowed simply never receives your last seen, photo or about.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static String timerLabel(int s) => switch (s) {
        86400 => '24 hours',
        604800 => '7 days',
        7776000 => '90 days',
        _ => 'Off',
      };

  Future<void> _save(BuildContext context) async {
    if (!kHasBackend || !Api.instance.loggedIn) return;
    final err = await Messenger.instance.pushPrivacy();
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        Widget row(String title, String value, VoidCallback onTap) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              title: Text(title, style: TextStyle(fontSize: 16, color: bc.text)),
              subtitle: Text(value, style: TextStyle(color: bc.muted)),
              onTap: onTap,
            );
        final statusLabel = switch (s.statusAudience) {
          1 => '${s.statusExcept.length} contacts excluded',
          2 => '${s.statusOnly.length} contacts included',
          3 => 'Close friends',
          _ => 'My contacts',
        };
        return Scaffold(
          appBar: AppBar(title: const Text('Privacy')),
          body: ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text('Who can see my personal info', style: TextStyle(color: bc.muted)),
            ),
            row('Last seen and online', s.lastSeenRule.label(), () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _LastSeenScreen()));
              if (context.mounted) await _save(context);
            }),
            row('Profile picture', s.photoRule.label(), () async {
              final r = await Navigator.of(context).push<PrivacyRule>(
                  MaterialPageRoute(builder: (_) => _RuleScreen(title: 'Profile picture', question: 'Who can see my profile picture', rule: s.photoRule)));
              if (r == null) return;
              s.toggle(() => s.photoRule = r);
              if (context.mounted) await _save(context);
            }),
            row('About', s.aboutRule.label(), () async {
              final r = await Navigator.of(context).push<PrivacyRule>(
                  MaterialPageRoute(builder: (_) => _RuleScreen(title: 'About', question: 'Who can see my About', rule: s.aboutRule)));
              if (r == null) return;
              s.toggle(() => s.aboutRule = r);
              if (context.mounted) await _save(context);
            }),
            row('Status', statusLabel, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatusPrivacyScreen()))),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              title: Text('Read receipts', style: TextStyle(fontSize: 16, color: bc.text)),
              subtitle: Text("If turned off, you won't send or receive Read receipts.", style: TextStyle(color: bc.muted)),
              value: s.readReceipts,
              onChanged: (v) => s.toggle(() => s.readReceipts = v),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              title: Text('App lock', style: TextStyle(fontSize: 16, color: bc.text)),
              subtitle: Text('Ask for fingerprint or screen lock when opening BAATLY', style: TextStyle(color: bc.muted)),
              value: s.appLock,
              onChanged: (v) => s.toggle(() => s.appLock = v),
            ),
            if (s.appLock)
              FutureBuilder<bool>(
                future: AppPin.isSet(),
                builder: (context, snap) {
                  final has = snap.data == true;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
                    title: Text(has ? 'App lock PIN is set' : 'Also allow a PIN', style: TextStyle(fontSize: 16, color: bc.text)),
                    subtitle: Text(has ? 'Tap to change or remove' : 'Unlock with a 6-digit BAATLY PIN as well as fingerprint', style: TextStyle(color: bc.muted)),
                    onTap: () async {
                      if (has) {
                        final v = await showModalBottomSheet<String>(
                          context: context,
                          builder: (sh) => SafeArea(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              ListTile(leading: const Icon(Icons.password_rounded), title: const Text('Change PIN'), onTap: () => Navigator.pop(sh, 'c')),
                              ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Remove PIN'), onTap: () => Navigator.pop(sh, 'r')),
                            ]),
                          ),
                        );
                        if (v == 'r') {
                          await AppPin.clear();
                          s.changed();
                          return;
                        }
                        if (v != 'c') return;
                      }
                      if (!context.mounted) return;
                      final pin = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NewPinScreen(title: 'App lock PIN', subtitle: 'Used to unlock BAATLY on this phone')));
                      if (pin == null) return;
                      await AppPin.set(pin);
                      s.changed();
                    },
                  );
                },
              ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
              child: Text('Screenshots', style: TextStyle(color: bc.muted)),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
              title: Text('View once photos', style: TextStyle(fontSize: 16, color: bc.text)),
              subtitle: Text('Screenshots are always blocked', style: TextStyle(color: bc.muted)),
              trailing: Text('Always', style: TextStyle(color: bc.muted)),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              title: Text('Locked chats', style: TextStyle(fontSize: 16, color: bc.text)),
              subtitle: Text('Block screenshots and screen recording in locked chats', style: TextStyle(color: bc.muted)),
              value: s.shotBlockLocked,
              onChanged: (v) => s.toggle(() => s.shotBlockLocked = v),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              title: Text('All of BAATLY', style: TextStyle(fontSize: 16, color: bc.text)),
              subtitle: Text('Block screenshots everywhere in the app. Blocked screens show black in recent apps and screen share.', style: TextStyle(color: bc.muted)),
              value: s.shotBlockAll,
              onChanged: (v) {
                s.toggle(() => s.shotBlockAll = v);
                SecureScreen.refresh();
              },
            ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
              child: Text('Disappearing messages', style: TextStyle(color: bc.muted)),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              title: Text('Default message timer', style: TextStyle(fontSize: 16, color: bc.text)),
              subtitle: Text('Start new chats with disappearing messages set to your timer', style: TextStyle(color: bc.muted)),
              trailing: Text(timerLabel(s.defaultTimer), style: TextStyle(color: bc.muted, fontSize: 15)),
              onTap: () => _timer(context),
            ),
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }

  Future<void> _timer(BuildContext context) async {
    final s = AppState.instance;
    var v = s.defaultTimer;
    final r = await showDialog<int>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: const Text('Default message timer'),
          content: RadioGroup<int>(
            groupValue: v,
            onChanged: (x) => setD(() => v = x ?? 0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final o in const [86400, 604800, 7776000, 0])
                RadioListTile<int>(value: o, contentPadding: EdgeInsets.zero, title: Text(timerLabel(o))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(d, v), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (r != null) s.toggle(() => s.defaultTimer = r);
  }
}

/// Everyone / My contacts / My contacts except… / Nobody.
class _RuleScreen extends StatefulWidget {
  final String title, question;
  final PrivacyRule rule;
  final Widget? footer;
  const _RuleScreen({required this.title, required this.question, required this.rule, this.footer});
  @override
  State<_RuleScreen> createState() => _RuleScreenState();
}

class _RuleScreenState extends State<_RuleScreen> {
  late int _m = widget.rule.m;
  late Set<String> _x = {...widget.rule.x};

  Future<void> _pickExcept() async {
    final picked = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(builder: (_) => ContactPickerScreen(title: 'Exclude contacts', initial: _x, excluding: true)),
    );
    if (picked != null) setState(() => _x = picked);
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(PrivacyRule(_m, _x));
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Text(widget.question, style: TextStyle(color: bc.muted)),
          ),
          RadioGroup<int>(
            groupValue: _m,
            onChanged: (v) async {
              setState(() => _m = v ?? 0);
              if (v == 2 && _x.isEmpty) await _pickExcept();
            },
            child: Column(children: [
              const RadioListTile<int>(value: 0, title: Text('Everyone')),
              const RadioListTile<int>(value: 1, title: Text('My contacts')),
              RadioListTile<int>(
                value: 2,
                title: const Text('My contacts except…'),
                subtitle: _m == 2
                    ? GestureDetector(
                        onTap: _pickExcept,
                        child: Text('${_x.length} excluded · Edit', style: TextStyle(color: context.primary, fontWeight: FontWeight.w600)),
                      )
                    : null,
              ),
              const RadioListTile<int>(value: 3, title: Text('Nobody')),
            ]),
          ),
          if (widget.footer != null) widget.footer!,
        ]),
      ),
    );
  }
}

class _LastSeenScreen extends StatelessWidget {
  const _LastSeenScreen();
  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Last seen and online')),
        body: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Text('Who can see my last seen', style: TextStyle(color: bc.muted)),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            title: Text(s.lastSeenRule.label()),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final r = await Navigator.of(context).push<PrivacyRule>(MaterialPageRoute(
                  builder: (_) => _RuleScreen(title: 'Last seen', question: 'Who can see my last seen', rule: s.lastSeenRule)));
              if (r != null) s.toggle(() => s.lastSeenRule = r);
            },
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
            child: Text('Who can see when I\'m online', style: TextStyle(color: bc.muted)),
          ),
          RadioGroup<int>(
            groupValue: s.onlineRule,
            onChanged: (v) => s.toggle(() => s.onlineRule = v ?? 0),
            child: const Column(children: [
              RadioListTile<int>(value: 0, title: Text('Everyone')),
              RadioListTile<int>(value: 1, title: Text('Same as last seen')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Text("If you don't share your last seen and online, you won't be able to see other people's last seen and online.",
                style: TextStyle(fontSize: 12.5, color: bc.muted)),
          ),
        ]),
      ),
    );
  }
}
