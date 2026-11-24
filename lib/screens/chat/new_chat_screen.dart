import 'package:flutter/material.dart';

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../data/api.dart';
import '../../data/app_state.dart';
import '../../data/contacts.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'chat_screen.dart';

class NewChatScreen extends StatelessWidget {
  const NewChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (kHasBackend && Api.instance.loggedIn) return const RealNewChatScreen();
    return _demo(context);
  }

  static final _contacts = [
    ('Ananya Gupta', 'AG', 1, 'Mumbai · Designer'),
    ('Neha (Office)', 'NO', 3, 'Finance team'),
    ('Somesh', 'S', 6, 'Building things'),
    ('Deepak Bhaiya', 'DB', 0, 'Chill, whatever happens'),
  ];

  Widget _demo(BuildContext context) {
    final bc = context.bc;
    final s = AppState.instance;
    final existing = s.chats.where((c) => !c.isGroup && !c.archived).toList();
    Widget action(IconData i, String t) => ListTile(
          leading: CircleAvatar(backgroundColor: context.primary, child: Icon(i, color: Colors.white)),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () => showComingSoon(context, t),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: ListView(children: [
        action(Icons.group_add_rounded, 'New group'),
        action(Icons.groups_rounded, 'New community'),
        action(Icons.person_add_alt_1_rounded, 'New contact'),
        const SectionLabel('Contacts on BAATLY'),
        for (final c in existing)
          ListTile(
            leading: Avatar(initials: c.initials, colorIndex: c.colorIndex, size: 44),
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(c.about, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(chat: c))),
          ),
        for (final c in _contacts)
          ListTile(
            leading: Avatar(initials: c.$2, colorIndex: c.$3, size: 44),
            title: Text(c.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(c.$4),
            onTap: () {
              final chat = Chat(id: c.$1, name: c.$1, initials: c.$2, colorIndex: c.$3, about: c.$4);
              s.toggle(() => s.chats.add(chat));
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
            },
          ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Demo build: these are sample contacts. Real contact sync comes later.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: bc.muted)),
        ),
      ]),
    );
  }
}


const kInviteLink = '$kDefaultApiBase/get';
String inviteText() =>
    "Let's chat on BAATLY! It's fast, private messaging with end-to-end encryption. Every conversation matters. Download: $kInviteLink";

/// Phone-book contacts: who is on BAATLY, and who can be invited.
class RealNewChatScreen extends StatefulWidget {
  const RealNewChatScreen({super.key});
  @override
  State<RealNewChatScreen> createState() => _RealNewChatScreenState();
}

class _RealNewChatScreenState extends State<RealNewChatScreen> {
  ContactsResult? _r;
  String? _error;
  bool _searching = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _r = null;
    });
    try {
      final r = await ContactBook.instance.load();
      if (mounted) setState(() => _r = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't read contacts. ($e)");
    }
  }

  void _open(BaatlyContact c) {
    final chat = Messenger.instance.chatWith(c);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
  }

  Future<void> _sms(PhoneContact c, String text) async {
    final uri = Uri.parse('sms:${c.e164}?body=${Uri.encodeComponent(text)}');
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) await SharePlus.instance.share(ShareParams(text: text));
  }

  void _invite(PhoneContact c) {
    final ctrl = TextEditingController(text: inviteText());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) {
        final bc = sheet.bc;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.of(sheet).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Send invite via SMS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: bc.text)),
            const SizedBox(height: 10),
            Text("${c.name} isn't on BAATLY. Do you want to invite them to join?",
                textAlign: TextAlign.center, style: TextStyle(color: bc.muted, height: 1.4)),
            const SizedBox(height: 18),
            Avatar(initials: Messenger.initialsOf(c.name), colorIndex: c.e164.hashCode.abs() % 7, size: 64),
            const SizedBox(height: 8),
            Text(c.name, style: TextStyle(fontWeight: FontWeight.w700, color: bc.text)),
            const SizedBox(height: 18),
            TextField(
              controller: ctrl,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                Navigator.pop(sheet);
                _sms(c, ctrl.text);
              },
              child: const Text('Send invite via SMS'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheet),
              child: Text('Not now', style: TextStyle(color: sheet.primary, fontWeight: FontWeight.w700)),
            ),
          ]),
        );
      },
    );
  }

  bool _match(String name, String phone) {
    if (_q.isEmpty) return true;
    final q = _q.toLowerCase();
    return name.toLowerCase().contains(q) || phone.replaceAll(' ', '').contains(q.replaceAll(' ', ''));
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final r = _r;
    final total = r == null ? null : r.onBaatly.length + r.invite.length;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: const InputDecoration(hintText: 'Search name or number', border: InputBorder.none),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Select contact'),
                if (total != null) Text('$total contacts', style: TextStyle(fontSize: 12, color: bc.muted)),
              ]),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searching = !_searching;
              _q = '';
            }),
          ),
          IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh', onPressed: _load),
        ],
      ),
      body: _body(context, r),
    );
  }

  Widget _body(BuildContext context, ContactsResult? r) {
    final bc = context.bc;
    if (_error != null) {
      return _message(context, Icons.wifi_off_rounded, _error!, 'Try again', _load);
    }
    if (r == null) return const Center(child: CircularProgressIndicator());
    if (!r.permission) {
      return _message(context, Icons.contacts_rounded,
          'Allow BAATLY to read your contacts to see who is on BAATLY. Your contact list is only matched, never stored on our server.',
          'Allow contacts', _load);
    }
    final on = r.onBaatly.where((c) => _match(c.name, c.phone)).toList();
    final inv = r.invite.where((c) => _match(c.name, c.number)).toList();
    final bold = TextStyle(fontWeight: FontWeight.w700, color: bc.text);
    return ListView(children: [
      if (_q.isEmpty)
        ListTile(
          leading: CircleAvatar(backgroundColor: context.primary, child: const Icon(Icons.share_rounded, color: Colors.white)),
          title: Text('Share invite link', style: bold),
          onTap: () => SharePlus.instance.share(ShareParams(text: inviteText())),
        ),
      if (on.isNotEmpty) const SectionLabel('Contacts on BAATLY'),
      for (final c in on)
        ListTile(
          leading: Avatar(initials: Messenger.initialsOf(c.name), colorIndex: c.userId.codeUnits.fold<int>(0, (a, b) => a + b) % 7, size: 44),
          title: Text(c.name, style: bold),
          subtitle: Text(c.about.isEmpty ? ContactBook.pretty(c.phone) : c.about, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _open(c),
        ),
      if (on.isEmpty && _q.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text('None of your contacts are on BAATLY yet. Invite them below!', style: TextStyle(color: bc.muted)),
        ),
      if (inv.isNotEmpty) const SectionLabel('Invite to BAATLY'),
      for (final c in inv)
        ListTile(
          leading: CircleAvatar(backgroundColor: bc.raised, child: Icon(Icons.person_rounded, color: bc.muted)),
          title: Text(c.name, style: bold, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(c.number),
          trailing: TextButton(
            onPressed: () => _invite(c),
            child: Text('Invite', style: TextStyle(color: context.primary, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          onTap: () => _invite(c),
        ),
      const SizedBox(height: 30),
    ]);
  }

  Widget _message(BuildContext context, IconData icon, String text, String button, VoidCallback onTap) {
    final bc = context.bc;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: context.primary),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: bc.muted, height: 1.4)),
          const SizedBox(height: 20),
          FilledButton(onPressed: onTap, child: Text(button)),
        ]),
      ),
    );
  }
}
