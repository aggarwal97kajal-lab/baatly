import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api.dart';
import '../../data/app_state.dart';
import '../../data/media.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../onboarding/splash_screen.dart';

String _bytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Text(text, style: TextStyle(fontSize: 13, color: context.bc.muted, height: 1.4)),
      );
}

// ======================================================================= Security
class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Security')),
        body: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Column(children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: context.primary.withOpacity(0.14), shape: BoxShape.circle),
                child: Icon(Icons.lock_rounded, size: 42, color: context.primary),
              ),
              const SizedBox(height: 14),
              Text('Your chats and calls are private', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: bc.text)),
              const SizedBox(height: 8),
              Text(
                'End-to-end encryption keeps your personal messages and calls between you and the people you choose. '
                'Not even BAATLY can read or listen to them.',
                textAlign: TextAlign.center,
                style: TextStyle(color: bc.muted, height: 1.4),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          for (final (icon, t) in const [
            (Icons.chat_outlined, 'Text and voice messages'),
            (Icons.call_outlined, 'Voice and video calls'),
            (Icons.photo_outlined, 'Photos, videos and documents'),
            (Icons.location_on_outlined, 'Location sharing'),
            (Icons.donut_large_rounded, 'Status updates'),
          ])
            ListTile(dense: true, leading: Icon(icon, color: context.primary), title: Text(t)),
          const Divider(),
          SwitchListTile(
            title: const Text('Show security notifications on this phone'),
            subtitle: const Text("Get told in the chat when a contact's security code changes, for example after they reinstall BAATLY or change phone."),
            value: s.securityNotices,
            onChanged: (v) => s.toggle(() => s.securityNotices = v),
          ),
          const _Note('To check that a chat is really end-to-end encrypted, open the chat → tap the name → Encryption, and compare the security code with your contact.'),
        ]),
      ),
    );
  }
}

// ======================================================================= Notifications
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: ListView(children: [
          const SectionLabel('Messages'),
          SwitchListTile(
            title: const Text('Message notifications'),
            subtitle: const Text('Show notifications for new messages'),
            value: s.notifMessages,
            onChanged: (v) => s.toggle(() => s.notifMessages = v),
          ),
          const SectionLabel('Groups'),
          SwitchListTile(
            title: const Text('Group notifications'),
            subtitle: const Text('Show notifications for new group messages'),
            value: s.notifGroups,
            onChanged: (v) => s.toggle(() => s.notifGroups = v),
          ),
          const SectionLabel('Privacy'),
          SwitchListTile(
            title: const Text('Show preview'),
            subtitle: const Text('Show message text inside notifications'),
            value: s.notifPreview,
            onChanged: (v) => s.toggle(() => s.notifPreview = v),
          ),
          const _Note(
              'Calls always ring. To mute one chat, open it → ⋮ → Mute notifications. '
              'To change the sound or vibration, open your phone Settings → Apps → BAATLY → Notifications.'),
        ]),
      ),
    );
  }
}

// ======================================================================= Storage and data
class StorageDataScreen extends StatefulWidget {
  const StorageDataScreen({super.key});
  @override
  State<StorageDataScreen> createState() => _StorageDataScreenState();
}

class _StorageDataScreenState extends State<StorageDataScreen> {
  int _sent = 0, _recv = 0;
  int? _used;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final files = await _StorageFiles.scan();
    if (!mounted) return;
    setState(() {
      _sent = p.getInt('net_sent') ?? 0;
      _recv = p.getInt('net_recv') ?? 0;
      _used = files.values.fold<int>(0, (a, l) => a + l.fold<int>(0, (x, f) => x + f.$2));
    });
  }

  static String _rule(int v) => switch (v) { 0 => 'Never', 1 => 'Wi-Fi only', _ => 'Wi-Fi and mobile data' };

  Future<void> _pickRule(String title, int current, void Function(int) set) async {
    final v = await showDialog<int>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(title),
        children: [
          for (final i in const [2, 1, 0])
            RadioListTile<int>(value: i, groupValue: current, title: Text(_rule(i)), onChanged: (x) => Navigator.pop(d, x)),
        ],
      ),
    );
    if (v != null) AppState.instance.toggle(() => set(v));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Storage and data')),
        body: ListView(children: [
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Manage storage'),
            subtitle: Text(_used == null ? 'Checking…' : '${_bytes(_used!)} used by BAATLY'),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageStorageScreen()));
              _load();
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_vert_rounded),
            title: const Text('Network usage'),
            subtitle: Text('${_bytes(_sent)} sent · ${_bytes(_recv)} received'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Network usage'),
                  content: Text('Media sent: ${_bytes(_sent)}\nMedia received: ${_bytes(_recv)}\n\nCounted on this phone since install or last reset.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Reset')),
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('OK')),
                  ],
                ),
              );
              if (ok == true) {
                final p = await SharedPreferences.getInstance();
                await p.remove('net_sent');
                await p.remove('net_recv');
                _load();
              }
            },
          ),
          const Divider(),
          const SectionLabel('Media auto-download'),
          ListTile(title: const Text('Photos'), subtitle: Text(_rule(s.autoPhotos)), onTap: () => _pickRule('Photos', s.autoPhotos, (v) => s.autoPhotos = v)),
          ListTile(title: const Text('Voice messages'), subtitle: Text(_rule(s.autoAudio)), onTap: () => _pickRule('Voice messages', s.autoAudio, (v) => s.autoAudio = v)),
          ListTile(title: const Text('Videos'), subtitle: Text(_rule(s.autoVideos)), onTap: () => _pickRule('Videos', s.autoVideos, (v) => s.autoVideos = v)),
          ListTile(title: const Text('Documents and audio files'), subtitle: Text(_rule(s.autoDocs)), onTap: () => _pickRule('Documents', s.autoDocs, (v) => s.autoDocs = v)),
          const _Note('Voice messages and stickers are small. Anything not downloaded automatically downloads when you tap it.'),
          const Divider(),
          const SectionLabel('Media upload quality'),
          RadioListTile<bool>(
            value: false,
            groupValue: s.hdPhotos,
            title: const Text('Standard quality'),
            subtitle: const Text('Faster to send, smaller files'),
            onChanged: (_) => s.toggle(() => s.hdPhotos = false),
          ),
          RadioListTile<bool>(
            value: true,
            groupValue: s.hdPhotos,
            title: const Text('HD quality'),
            subtitle: const Text('Sharper photos, bigger files'),
            onChanged: (_) => s.toggle(() => s.hdPhotos = true),
          ),
        ]),
      ),
    );
  }
}

/// Files BAATLY keeps on this phone, by type.
class _StorageFiles {
  static const images = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'bmp'};
  static const videos = {'mp4', 'mov', '3gp', 'mkv', 'webm', 'avi'};
  static const audio = {'m4a', 'aac', 'mp3', 'ogg', 'opus', 'wav', 'amr', 'flac'};

  static Future<Map<String, List<(File, int)>>> scan() async {
    final out = <String, List<(File, int)>>{'Photos': [], 'Videos': [], 'Voice and audio': [], 'Documents': [], 'Stickers': []};
    Future<void> walk(Directory d, String? force) async {
      if (!d.existsSync()) return;
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        int len;
        try {
          len = await e.length();
        } catch (_) {
          continue;
        }
        final ext = MediaFiles.ext(e.path);
        final k = force ??
            (images.contains(ext)
                ? 'Photos'
                : videos.contains(ext)
                    ? 'Videos'
                    : audio.contains(ext)
                        ? 'Voice and audio'
                        : 'Documents');
        out[k]!.add((e, len));
      }
    }

    await walk(await MediaFiles.dir(), null);
    final docs = await getApplicationDocumentsDirectory();
    await walk(Directory('${docs.path}/stickers/mine'), 'Stickers');
    return out;
  }
}

class ManageStorageScreen extends StatefulWidget {
  const ManageStorageScreen({super.key});
  @override
  State<ManageStorageScreen> createState() => _ManageStorageScreenState();
}

class _ManageStorageScreenState extends State<ManageStorageScreen> {
  Map<String, List<(File, int)>>? _files;
  int _cache = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await _StorageFiles.scan();
    var cache = 0;
    try {
      final t = await getTemporaryDirectory();
      await for (final e in t.list(recursive: true, followLinks: false)) {
        if (e is File) cache += await e.length();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _files = f;
        _cache = cache;
      });
    }
  }

  Future<void> _delete(String kind) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete all ${kind.toLowerCase()}?'),
        content: const Text('They will be removed from this phone. Chats stay. Files you received can usually be downloaded again for a while; files you sent cannot.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    for (final (f, _) in _files![kind]!) {
      try {
        await f.delete();
      } catch (_) {}
    }
    AppState.instance.changed();
    await _load();
  }

  Future<void> _clearCache() async {
    try {
      final t = await getTemporaryDirectory();
      await for (final e in t.list(followLinks: false)) {
        try {
          await e.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared')));
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final f = _files;
    final total = f == null ? 0 : f.values.fold<int>(0, (a, l) => a + l.fold<int>(0, (x, e) => x + e.$2));
    final colors = [const Color(0xFF2E7D8C), const Color(0xFFC8553D), const Color(0xFF7A5BA6), const Color(0xFF3D7DC8), const Color(0xFFE9A23B)];
    return Scaffold(
      appBar: AppBar(title: const Text('Manage storage')),
      body: f == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_bytes(total), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: bc.text)),
                  Text('Used by BAATLY on this phone', style: TextStyle(color: bc.muted)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 10,
                      child: total == 0
                          ? ColoredBox(color: bc.raised)
                          : Row(children: [
                              for (final (i, k) in f.keys.indexed)
                                if (f[k]!.isNotEmpty)
                                  Expanded(
                                    flex: (f[k]!.fold<int>(0, (x, e) => x + e.$2) * 1000 ~/ total).clamp(1, 1000),
                                    child: ColoredBox(color: colors[i % colors.length]),
                                  ),
                            ]),
                    ),
                  ),
                ]),
              ),
              for (final (i, k) in f.keys.indexed)
                ListTile(
                  leading: CircleAvatar(radius: 7, backgroundColor: colors[i % colors.length]),
                  title: Text(k),
                  subtitle: Text('${f[k]!.length} file${f[k]!.length == 1 ? '' : 's'} · ${_bytes(f[k]!.fold<int>(0, (x, e) => x + e.$2))}'),
                  trailing: f[k]!.isEmpty ? null : TextButton(onPressed: () => _delete(k), child: const Text('Delete')),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Clear cache'),
                subtitle: Text('${_bytes(_cache)} of temporary files'),
                onTap: _clearCache,
              ),
            ]),
    );
  }
}

// ======================================================================= Linked devices
class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({super.key});
  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  List<Map<String, dynamic>>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.instance.request('GET', '/v1/me/sessions');
      if (!mounted) return;
      setState(() {
        _list = [for (final x in (d['sessions'] as List? ?? [])) (x as Map).cast<String, dynamic>()];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : "Couldn't load devices");
    }
  }

  String _ago(num? ms) {
    if (ms == null) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 2) return 'Active now';
    if (d.inHours < 1) return 'Last active ${d.inMinutes} min ago';
    if (d.inDays < 1) return 'Last active ${d.inHours} h ago';
    return 'Last active ${t.day}/${t.month}/${t.year}';
  }

  Future<void> _logout(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Log out this device?'),
        content: Text('${s['device'] ?? 'This device'} will be logged out of BAATLY.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.instance.request('DELETE', '/v1/me/sessions/${s['id']}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : "Couldn't log out")));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final list = _list;
    final others = list?.where((s) => s['current'] != true).toList() ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Linked devices')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Column(children: [
              Icon(Icons.devices_rounded, size: 64, color: context.primary),
              const SizedBox(height: 10),
              Text('Places where your account is logged in', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: bc.text)),
              const SizedBox(height: 6),
              Text("If you don't recognise a device, log it out.", textAlign: TextAlign.center, style: TextStyle(color: bc.muted)),
            ]),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: bc.muted)))
          else if (list == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else ...[
            for (final s in list)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: context.primary.withOpacity(0.14),
                  child: Icon(Icons.smartphone_rounded, color: context.primary),
                ),
                title: Text((s['device'] as String?)?.isNotEmpty == true ? s['device'] as String : 'Android phone'),
                subtitle: Text(s['current'] == true ? 'This phone' : _ago(s['last_seen_at'] as num?)),
                trailing: s['current'] == true ? null : TextButton(onPressed: () => _logout(s), child: const Text('Log out')),
              ),
            if (others.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: OutlinedButton(
                  onPressed: () async {
                    for (final s in others) {
                      try {
                        await Api.instance.request('DELETE', '/v1/me/sessions/${s['id']}');
                      } catch (_) {}
                    }
                    _load();
                  },
                  child: const Text('Log out all other devices'),
                ),
              ),
          ],
          const _Note(
              'Messages are end-to-end encrypted for one phone at a time: the phone you logged in on last gets your new messages. '
              'Using the same account on two phones at once is coming in a future update.'),
        ]),
      ),
    );
  }
}

// ======================================================================= Help
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.help_outline_rounded),
          title: const Text('Help centre'),
          subtitle: const Text('Answers to common questions'),
          onTap: () => go(const _FaqScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.chat_bubble_outline_rounded),
          title: const Text('Contact us'),
          subtitle: const Text('Questions or something not working'),
          onTap: () => go(const SupportScreen(kind: 'help')),
        ),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Send feedback'),
          subtitle: const Text('Report a technical problem'),
          onTap: () => go(const SupportScreen(kind: 'problem')),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Terms and Privacy Policy'),
          onTap: () => go(const _PolicyScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline_rounded),
          title: const Text('App info'),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'BAATLY',
            applicationVersion: '0.1.0',
            applicationLegalese: 'Every Conversation Matters',
          ),
        ),
      ]),
    );
  }
}

/// "Contact us" / "Send feedback": a message (and screenshots) straight to
/// the BAATLY team from inside the app.
class SupportScreen extends StatefulWidget {
  final String kind; // help | problem
  const SupportScreen({super.key, required this.kind});
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _text = TextEditingController();
  final _shots = <String>[];
  bool _sending = false;

  Future<void> _addShot() async {
    if (_shots.length >= 3) return;
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 70);
      if (f != null) setState(() => _shots.add(f.path));
    } catch (_) {}
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.length < 3) return;
    setState(() => _sending = true);
    try {
      final shots = <String>[for (final p in _shots) base64Encode(await File(p).readAsBytes())];
      await Api.instance.request('POST', '/v1/support', {
        'text': t,
        'kind': widget.kind,
        'device': Api.deviceName,
        'version': '0.1.0',
        'shots': shots,
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Thanks!'),
          content: const Text("We got your message and will look into it. We'll reply in BAATLY if we need more details."),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : "Couldn't send. Check your internet.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final problem = widget.kind == 'problem';
    return Scaffold(
      appBar: AppBar(title: Text(problem ? 'Send feedback' : 'Contact us')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                problem ? 'Tell us what went wrong. Screenshots help us fix it faster.' : 'How can we help? Write your question below.',
                style: TextStyle(color: bc.muted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _text,
                minLines: 5,
                maxLines: 10,
                maxLength: 5000,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: problem ? 'Describe the technical issue' : 'Write your message',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              Text('Screenshots (optional)', style: TextStyle(fontWeight: FontWeight.w600, color: bc.text)),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final p in _shots)
                  Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(p), width: 96, height: 120, fit: BoxFit.cover)),
                    Positioned(
                      right: -8,
                      top: -8,
                      child: IconButton.filled(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: () => setState(() => _shots.remove(p)),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ]),
                if (_shots.length < 3)
                  InkWell(
                    onTap: _addShot,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 96,
                      height: 120,
                      decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.add_photo_alternate_outlined, color: bc.muted),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              Text('Your phone model and app version are sent with your message so we can help.', style: TextStyle(fontSize: 12.5, color: bc.muted)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _sending || _text.text.trim().length < 3 ? null : _send,
                child: _sending ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Send'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _FaqScreen extends StatelessWidget {
  const _FaqScreen();
  static const _faq = [
    ('Can BAATLY read my messages?',
        'No. Messages, photos, voice notes, calls and status updates are end-to-end encrypted on your phone. Our server only passes along locked data it cannot open.'),
    ('Why do my contacts not show up?',
        'Only people who have installed BAATLY appear in your list. Allow contacts access, then use "Invite" to send BAATLY to the rest.'),
    ('How do I delete a message for everyone?',
        'Long-press the message and tap "Delete for everyone". This works for a short time after sending.'),
    ('How do I make a sticker from my photo?',
        'Open a chat → emoji button → Sticker tab → Create. BAATLY removes the background for you.'),
    ('How do group calls work?',
        'Open a group and tap the call or video button. Everyone gets a ring; up to 4 people can be in a call together.'),
    ('What is a community?',
        'A set of related groups with one announcement group where admins can reach everyone. Find it in New chat → Communities.'),
    ('Calls don\'t connect on mobile data',
        'Some mobile networks block direct calls. Try Wi-Fi for now; we are adding a relay so calls work on every network.'),
    ('How do I hide a chat?',
        'Long-press a chat and choose "Lock chat". Locked chats open only with your fingerprint.'),
    ('How do I free up space?',
        'Go to You → Storage and data → Manage storage, and delete the media you don\'t need.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help centre')),
      body: ListView(children: [
        for (final (q, a) in _faq)
          ExpansionTile(
            title: Text(q, style: const TextStyle(fontWeight: FontWeight.w600)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            expandedAlignment: Alignment.centerLeft,
            children: [Text(a, style: TextStyle(color: context.bc.muted, height: 1.4))],
          ),
      ]),
    );
  }
}

class _PolicyScreen extends StatelessWidget {
  const _PolicyScreen();
  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    Widget h(String t) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 6), child: Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: bc.text)));
    Widget p(String t) => Text(t, style: TextStyle(color: bc.muted, height: 1.45));
    return Scaffold(
      appBar: AppBar(title: const Text('Terms and Privacy Policy')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        h('What we can see'),
        p('Your phone number, profile name, about, profile photo (shown as your privacy settings allow), who you have blocked, and when you were last online. We use these only to run BAATLY.'),
        h('What we cannot see'),
        p('The content of your messages, calls, media, locations and status updates. They are end-to-end encrypted and are deleted from our server once delivered (or after they expire).'),
        h('Contacts'),
        p('Your phone contacts are only matched to find who uses BAATLY. We keep only the matches, never your full contact list.'),
        h('Your choices'),
        p('You control who sees your last seen, photo and about in Privacy. You can delete your account at any time from You → Account; this removes your data from our server.'),
        h('Using BAATLY fairly'),
        p('Don\'t use BAATLY to send spam, harass people, or share illegal content. Accounts that are reported and found doing this can be limited or removed.'),
        const SizedBox(height: 18),
        p('Questions? Go to You → Help → Contact us.'),
      ]),
    );
  }
}

// ======================================================================= Account
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  static String _last10(String t) {
    final d = t.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  Future<void> _delete(BuildContext context) async {
    final ctrl = TextEditingController();
    final phone = AppState.instance.phone;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Delete my account'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This deletes your account, profile and status from BAATLY. Messages on this phone are removed too. This can\'t be undone.'),
            const SizedBox(height: 12),
            Text('Type your number to confirm: $phone'),
            TextField(controller: ctrl, keyboardType: TextInputType.phone, onChanged: (_) => set(() {})),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(
              onPressed: _last10(ctrl.text).length == 10 && _last10(ctrl.text) == _last10(phone) ? () => Navigator.pop(d, true) : null,
              child: const Text('Delete', style: TextStyle(color: Color(0xFFD32F2F))),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await Api.instance.deleteAccount();
      await AppState.instance.resetDemo();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const SplashScreen()), (_) => false);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : "Couldn't delete. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.phone_outlined), title: const Text('Phone number'), subtitle: Text(s.phone.isEmpty ? '—' : s.phone)),
        if (s.username.isNotEmpty) ListTile(leading: const Icon(Icons.alternate_email_rounded), title: const Text('Username'), subtitle: Text('@${s.username}')),
        ListTile(
          leading: const Icon(Icons.devices_rounded),
          title: const Text('Linked devices'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LinkedDevicesScreen())),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.delete_forever_outlined, color: Color(0xFFD32F2F)),
          title: const Text('Delete my account', style: TextStyle(color: Color(0xFFD32F2F))),
          onTap: () => _delete(context),
        ),
      ]),
    );
  }
}
