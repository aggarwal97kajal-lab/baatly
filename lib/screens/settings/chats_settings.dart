import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/app_state.dart';
import '../../data/backup.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'appearance_screen.dart';
import 'wallpaper_screen.dart';

String _size(int b) {
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String _when(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${t.day} ${months[t.month - 1]}, $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}

class ChatsSettingsScreen extends StatelessWidget {
  const ChatsSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Chats')),
        body: ListView(children: [
          const SectionLabel('Display'),
          ListTile(title: const Text('Theme'), onTap: () => go(const AppearanceScreen())),
          ListTile(title: const Text('Chat wallpaper'), subtitle: Text(s.wallpaper.label), onTap: () => go(const WallpaperScreen())),
          const SectionLabel('Archived chats'),
          SwitchListTile(
            title: const Text('Keep chats archived'),
            subtitle: const Text('Archived chats will remain archived when you receive a new message'),
            value: s.keepArchived,
            onChanged: (v) => s.toggle(() => s.keepArchived = v),
          ),
          const Divider(),
          ListTile(leading: const Icon(Icons.cloud_upload_outlined), title: const Text('Chat backup'), onTap: () => go(const ChatBackupScreen())),
          ListTile(leading: const Icon(Icons.history_rounded), title: const Text('Chat history'), onTap: () => go(const ChatHistoryScreen())),
        ]),
      ),
    );
  }
}

// ======================================================================= Chat backup
class ChatBackupScreen extends StatefulWidget {
  const ChatBackupScreen({super.key});
  @override
  State<ChatBackupScreen> createState() => _ChatBackupScreenState();
}

class _ChatBackupScreenState extends State<ChatBackupScreen> {
  final b = BackupService.instance;

  @override
  void initState() {
    super.initState();
    b.load();
  }

  static String _auto(int v) => switch (v) { 1 => 'Daily', 2 => 'Weekly', 3 => 'Monthly', _ => 'Off' };

  void _err() {
    if (b.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(b.error!), duration: const Duration(seconds: 5)));
    }
  }

  Future<void> _backup() async {
    final ok = await b.backup();
    if (ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup complete')));
    _err();
  }

  Future<void> _restore() async {
    final info = await b.remoteInfo(interactive: true);
    if (!mounted) return;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(b.error ?? 'No backup found in this Google account')));
      return;
    }
    String? pw;
    if (info.encrypted) {
      pw = await _askPassword(title: 'Enter backup password', confirm: false);
      if (pw == null) return;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Restore backup?'),
          content: Text('Backup from ${_when(info.at)} (${_size(info.size)}). Chats on this phone will be replaced.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Restore')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final ok = await b.restore(password: pw);
    if (ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chats restored')));
    _err();
  }

  Future<String?> _askPassword({required String title, bool confirm = true}) async {
    final a = TextEditingController(), c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) {
          final ok = a.text.length >= 6 && (!confirm || a.text == c.text);
          return AlertDialog(
            title: Text(title),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              if (confirm)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text("Only you can open this backup. If you forget the password, the backup can't be restored. BAATLY can't reset it."),
                ),
              TextField(controller: a, obscureText: true, autofocus: true, onChanged: (_) => set(() {}), decoration: const InputDecoration(labelText: 'Password (6+ characters)')),
              if (confirm) TextField(controller: c, obscureText: true, onChanged: (_) => set(() {}), decoration: const InputDecoration(labelText: 'Confirm password')),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
              TextButton(onPressed: ok ? () => Navigator.pop(d, a.text) : null, child: const Text('OK')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return ListenableBuilder(
      listenable: b,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Chat backup')),
        body: ListView(children: [
          if (b.error != null && !b.busy)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFE9A23B).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFE9A23B)),
                const SizedBox(width: 10),
                Expanded(child: Text(b.error!, style: TextStyle(color: bc.text))),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.cloud_upload_outlined, color: context.primary, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Backup settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: bc.text)),
                  const SizedBox(height: 4),
                  Text("Back up your chats and media to Google Drive so you don't lose them when you change phone.",
                      style: TextStyle(color: bc.muted, fontSize: 13, height: 1.4)),
                  const SizedBox(height: 12),
                  Text('Last backup: ${b.lastAt == null ? 'Never' : _when(b.lastAt!)}', style: TextStyle(color: bc.text, fontSize: 13.5)),
                  Text('Size: ${b.lastSize > 0 ? _size(b.lastSize) : '—'}', style: TextStyle(color: bc.text, fontSize: 13.5)),
                  const SizedBox(height: 14),
                  if (b.busy) ...[
                    Text(b.stage ?? 'Working…', style: TextStyle(color: bc.muted)),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: b.progress, borderRadius: BorderRadius.circular(4)),
                    if (b.progress != null)
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text('${(b.progress! * 100).round()}%', style: TextStyle(fontSize: 12, color: bc.muted))),
                  ] else
                    Wrap(spacing: 10, runSpacing: 8, children: [
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(110, 42), padding: const EdgeInsets.symmetric(horizontal: 22)),
                        onPressed: _backup,
                        child: const Text('Back up'),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(100, 42), padding: const EdgeInsets.symmetric(horizontal: 20)),
                        onPressed: _restore,
                        child: const Text('Restore'),
                      ),
                    ]),
                ]),
              ),
            ]),
          ),
          const Divider(),
          ListTile(
            title: const Text('Google Account'),
            subtitle: Text(b.email ?? 'Tap to choose'),
            onTap: b.busy
                ? null
                : () async {
                    await b.chooseAccount();
                    _err();
                  },
          ),
          ListTile(
            title: const Text('Automatic backups'),
            subtitle: Text(_auto(b.auto)),
            onTap: () async {
              final v = await showDialog<int>(
                context: context,
                builder: (d) => SimpleDialog(title: const Text('Automatic backups'), children: [
                  for (final i in const [1, 2, 3, 0])
                    RadioListTile<int>(
                      value: i,
                      groupValue: b.auto,
                      title: Text(i == 0 ? 'Off (only when I tap "Back up")' : _auto(i)),
                      onChanged: (x) => Navigator.pop(d, x),
                    ),
                ]),
              );
              if (v != null) b.set(() => b.auto = v);
            },
          ),
          SwitchListTile(
            title: const Text('Back up over mobile data'),
            value: b.overMobile,
            onChanged: (v) => b.set(() => b.overMobile = v),
          ),
          SwitchListTile(
            title: const Text('Include videos'),
            value: b.includeVideos,
            onChanged: (v) => b.set(() => b.includeVideos = v),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('End-to-end encryption', style: TextStyle(fontWeight: FontWeight.w700, color: bc.text)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline_rounded),
            title: const Text('End-to-end encrypted backup'),
            subtitle: Text(b.encrypted ? 'On · protected with your password' : 'Off'),
            value: b.encrypted,
            onChanged: (v) async {
              if (v) {
                final pw = await _askPassword(title: 'Create a backup password');
                if (pw != null) await b.setPassword(pw);
              } else {
                await b.setPassword(null);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              'The backup is kept in a private BAATLY folder in your Google Drive and uses your Google storage. '
              'Automatic backups run when you open BAATLY and one is due.',
              style: TextStyle(fontSize: 12.5, color: bc.muted),
            ),
          ),
        ]),
      ),
    );
  }
}

// ======================================================================= Chat history
class ChatHistoryScreen extends StatelessWidget {
  const ChatHistoryScreen({super.key});

  Future<bool> _confirm(BuildContext context, String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

  Future<void> _export(BuildContext context) async {
    final chats = AppState.instance.chats.where((c) => c.messages.isNotEmpty).toList();
    final chat = await showModalBottomSheet<Chat>(
      context: context,
      isScrollControlled: true,
      builder: (s) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            const ListTile(title: Text('Export chat', style: TextStyle(fontWeight: FontWeight.w700))),
            for (final c in chats)
              ListTile(
                leading: Avatar(initials: c.initials, colorIndex: c.colorIndex, photo: c.photo, size: 40),
                title: Text(c.name),
                onTap: () => Navigator.pop(s, c),
              ),
          ]),
        ),
      ),
    );
    if (chat == null || !context.mounted) return;
    final withMedia = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Export chat'),
        content: const Text('Including media makes the export bigger.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Without media')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Include media')),
        ],
      ),
    );
    if (withMedia == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    final b = StringBuffer();
    final files = <XFile>[];
    for (final m in chat.messages) {
      if (m.kind == MsgKind.system) continue;
      final t = m.time;
      final who = m.fromMe ? AppState.instance.name : (chat.isRealGroup && m.from != null ? Messenger.instance.nameFor(m.from!) : chat.name);
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      var body = m.deleted ? 'This message was deleted' : m.text;
      final path = m.mediaPath;
      if (!m.deleted && path != null && m.kind != MsgKind.text) {
        final name = path.split('/').last;
        if (withMedia && File(path).existsSync()) {
          files.add(XFile(path));
          body = '$name (file attached)${body.isEmpty ? '' : '\n$body'}';
        } else {
          body = '<Media omitted>${body.isEmpty ? '' : '\n$body'}';
        }
      }
      b.writeln('${two(t.day)}/${two(t.month)}/${t.year % 100}, $h:${two(t.minute)} ${t.hour < 12 ? 'am' : 'pm'} - $who: $body');
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/BAATLY Chat with ${chat.name.replaceAll(RegExp(r'[^\w ]'), '')}.txt');
    await f.writeAsString(b.toString());
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path), ...files.take(100)], subject: 'BAATLY chat with ${chat.name}'));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Chat history')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.ios_share_rounded), title: const Text('Export chat'), onTap: () => _export(context)),
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: const Text('Archive all chats'),
          onTap: () async {
            if (!await _confirm(context, 'Archive all chats?', 'You can find them later in Archived.', 'Archive')) return;
            s.toggle(() {
              for (final c in s.chats) {
                c.archived = true;
              }
            });
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All chats archived')));
          },
        ),
        ListTile(
          leading: const Icon(Icons.remove_circle_outline_rounded),
          title: const Text('Clear all chats'),
          onTap: () async {
            if (!await _confirm(context, 'Clear all chats?', 'Messages in all chats will be deleted from this phone. Starred messages are kept.', 'Clear')) return;
            s.toggle(() {
              for (final c in s.chats) {
                c.messages.removeWhere((m) => !m.starred);
              }
            });
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFD32F2F)),
          title: const Text('Delete all chats', style: TextStyle(color: Color(0xFFD32F2F))),
          onTap: () async {
            if (!await _confirm(context, 'Delete all chats?', 'All chats and their messages will be deleted from this phone.', 'Delete')) return;
            for (final c in [...s.chats]) {
              s.deleteChat(c);
            }
          },
        ),
      ]),
    );
  }
}
