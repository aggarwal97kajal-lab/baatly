import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';
import '../chat/links.dart';

/// WhatsApp-style search: filters + recent searches, then chats and messages as you type.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  String _q = '';
  String? _chip;
  List<String> _recent = [];

  static const _chips = [
    ('Unread', Icons.mark_chat_unread_outlined),
    ('Photos', Icons.photo_outlined),
    ('Videos', Icons.videocam_outlined),
    ('Links', Icons.link_rounded),
    ('Documents', Icons.description_outlined),
  ];
  static final _url = RegExp(r'https?://[^\s]+', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _recent = p.getStringList('recent_search') ?? []);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<Chat> get _chats => AppState.instance.chats.where((c) => !c.locked).toList();

  Future<void> _open(Chat chat, {bool remember = true}) async {
    if (remember) {
      final p = await SharedPreferences.getInstance();
      _recent = [chat.id, ..._recent.where((x) => x != chat.id)].take(10).toList();
      await p.setStringList('recent_search', _recent);
      if (mounted) setState(() {});
    }
    AppState.instance.openChat(chat);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
  }

  Future<void> _clearRecent() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('recent_search');
    setState(() => _recent = []);
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Scaffold(
      backgroundColor: bc.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Container(
              height: 52,
              decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(26)),
              child: Row(children: [
                IconButton(icon: Icon(Icons.arrow_back_rounded, color: bc.text), onPressed: () => Navigator.pop(context)),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    onChanged: (v) => setState(() => _q = v.trim()),
                    style: TextStyle(color: bc.text, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: _chip == null ? 'Search' : 'Search ${_chip!.toLowerCase()}',
                      hintStyle: TextStyle(color: bc.muted),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (_q.isNotEmpty || _chip != null)
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: bc.muted),
                    onPressed: () => setState(() {
                      _ctrl.clear();
                      _q = '';
                      _chip = null;
                    }),
                  ),
              ]),
            ),
          ),
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: [
                for (final (label, icon) in _chips)
                  if (_chip == null || _chip == label)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: _chip == label,
                        showCheckmark: false,
                        avatar: Icon(icon, size: 18, color: _chip == label ? Theme.of(context).colorScheme.onPrimary : bc.text),
                        label: Text(label),
                        labelStyle: TextStyle(color: _chip == label ? Theme.of(context).colorScheme.onPrimary : bc.text),
                        selectedColor: context.primary,
                        backgroundColor: bc.raised,
                        side: BorderSide.none,
                        shape: const StadiumBorder(),
                        onSelected: (v) => setState(() => _chip = v ? label : null),
                      ),
                    ),
              ],
            ),
          ),
          Expanded(child: _body(bc)),
        ]),
      ),
    );
  }

  Widget _body(BaatlyColors bc) {
    if (_chip != null) return _chipResults(bc);
    if (_q.isEmpty) return _recentView(bc);
    final q = _q.toLowerCase();
    final chats = _chats.where((c) => c.name.toLowerCase().contains(q)).toList();
    final msgs = <(Chat, Message)>[
      for (final c in _chats)
        for (final m in c.messages.reversed)
          if (!m.deleted && m.kind != MsgKind.system && m.kind != MsgKind.call && m.text.toLowerCase().contains(q)) (c, m),
    ]..sort((a, b) => b.$2.time.compareTo(a.$2.time));
    if (chats.isEmpty && msgs.isEmpty) {
      return Center(child: Text('No results for "$_q"', style: TextStyle(color: bc.muted)));
    }
    return ListView(children: [
      if (chats.isNotEmpty) _section('Chats', bc),
      for (final c in chats) _chatTile(c, bc),
      if (msgs.isNotEmpty) _section('Messages', bc),
      for (final (c, m) in msgs.take(200))
        InkWell(
          onTap: () => _open(c),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    c.isGroup && !m.fromMe && m.from != null ? '${Messenger.instance.nameFor(m.from!)} · ${c.name}' : (m.fromMe ? 'You · ${c.name}' : c.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: bc.muted),
                  ),
                ),
                Text(_date(m.time), style: TextStyle(fontSize: 12, color: bc.muted)),
              ]),
              const SizedBox(height: 3),
              _highlight(m.text.replaceAll('\n', ' '), q, TextStyle(fontSize: 15, color: bc.text), maxLines: 2),
            ]),
          ),
        ),
    ]);
  }

  Widget _section(String t, BaatlyColors bc) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Text(t, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: bc.muted)),
      );

  Widget _chatTile(Chat c, BaatlyColors bc) {
    final m = c.last;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      leading: Avatar(initials: c.initials, colorIndex: c.colorIndex, photo: c.photo, size: 50),
      title: _highlight(c.name, _q.toLowerCase(), TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: bc.text)),
      subtitle: m == null ? null : Text(_preview(m), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: bc.muted)),
      trailing: m == null ? null : Text(_date(m.time), style: TextStyle(fontSize: 12, color: bc.muted)),
      onTap: () => _open(c),
    );
  }

  static String _preview(Message m) => switch (m.kind) {
        MsgKind.image => 'Photo',
        MsgKind.video => 'Video',
        MsgKind.voice => 'Voice message',
        MsgKind.doc => (m.media?['name'] as String?) ?? 'Document',
        MsgKind.call => m.media?['v'] == true ? 'Video call' : 'Voice call',
        _ => m.text.replaceAll('\n', ' '),
      };

  static String _date(DateTime t) {
    final now = DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    if (d == today) return hhmm(t);
    if (today.difference(d).inDays == 1) return 'Yesterday';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${(t.year % 100).toString().padLeft(2, '0')}';
  }

  Widget _highlight(String text, String q, TextStyle style, {int maxLines = 1}) {
    if (q.isEmpty) return Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (true) {
      final j = lower.indexOf(q, i);
      if (j < 0) {
        spans.add(TextSpan(text: text.substring(i)));
        break;
      }
      if (j > i) spans.add(TextSpan(text: text.substring(i, j)));
      spans.add(TextSpan(text: text.substring(j, j + q.length), style: TextStyle(color: context.primary, fontWeight: FontWeight.w700)));
      i = j + q.length;
    }
    return Text.rich(TextSpan(style: style, children: spans), maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }

  Widget _recentView(BaatlyColors bc) {
    final byId = {for (final c in _chats) c.id: c};
    final recent = [for (final id in _recent) if (byId[id] != null) byId[id]!];
    if (recent.isEmpty) {
      return Center(child: Text('Search chats, people and messages', style: TextStyle(color: bc.muted)));
    }
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
        child: Row(children: [
          Expanded(child: Text('Recent searches', style: TextStyle(fontSize: 14, color: bc.muted))),
          TextButton(
            style: TextButton.styleFrom(backgroundColor: bc.raised, foregroundColor: bc.text, shape: const StadiumBorder()),
            onPressed: _clearRecent,
            child: const Text('Clear all'),
          ),
        ]),
      ),
      SizedBox(
        height: 96,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final c in recent)
              GestureDetector(
                onTap: () => _open(c),
                child: SizedBox(
                  width: 78,
                  child: Column(children: [
                    Avatar(initials: c.initials, colorIndex: c.colorIndex, photo: c.photo, size: 60),
                    const SizedBox(height: 6),
                    Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: bc.muted)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  Widget _chipResults(BaatlyColors bc) {
    final q = _q.toLowerCase();
    bool nameOk(Chat c) => q.isEmpty || c.name.toLowerCase().contains(q);
    switch (_chip) {
      case 'Unread':
        final list = _chats.where((c) => c.unread > 0 && nameOk(c)).toList();
        if (list.isEmpty) return Center(child: Text('No unread chats', style: TextStyle(color: bc.muted)));
        return ListView(children: [for (final c in list) _chatTile(c, bc)]);
      case 'Photos':
      case 'Videos':
        final kind = _chip == 'Photos' ? MsgKind.image : MsgKind.video;
        final items = <(Chat, Message)>[
          for (final c in _chats)
            for (final m in c.messages)
              if (!m.deleted && m.kind == kind && m.media?['once'] != true && m.media?['stk'] != true && (q.isEmpty || m.text.toLowerCase().contains(q) || c.name.toLowerCase().contains(q)))
                (c, m),
        ]..sort((a, b) => b.$2.time.compareTo(a.$2.time));
        if (items.isEmpty) return Center(child: Text('No ${_chip!.toLowerCase()}', style: TextStyle(color: bc.muted)));
        return GridView.count(
          crossAxisCount: 3,
          padding: const EdgeInsets.all(2),
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          children: [
            for (final (c, m) in items)
              GestureDetector(
                onTap: () => _open(c, remember: false),
                child: Stack(fit: StackFit.expand, children: [
                  _thumb(m, bc),
                  if (kind == MsgKind.video) const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 34)),
                ]),
              ),
          ],
        );
      case 'Links':
        final items = <(Chat, Message, String)>[
          for (final c in _chats)
            for (final m in c.messages)
              if (!m.deleted)
                for (final u in _url.allMatches(m.text))
                  if (q.isEmpty || u.group(0)!.toLowerCase().contains(q) || m.text.toLowerCase().contains(q)) (c, m, u.group(0)!),
        ]..sort((a, b) => b.$2.time.compareTo(a.$2.time));
        if (items.isEmpty) return Center(child: Text('No links', style: TextStyle(color: bc.muted)));
        return ListView(children: [
          for (final (c, m, u) in items)
            ListTile(
              leading: CircleAvatar(backgroundColor: bc.raised, child: Icon(Icons.link_rounded, color: bc.text)),
              title: Text(u, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.primary, fontSize: 14)),
              subtitle: Text('${c.name} · ${_date(m.time)}', style: TextStyle(color: bc.muted, fontSize: 12.5)),
              onTap: () => openLink(context, u),
              onLongPress: () => _open(c, remember: false),
            ),
        ]);
      default:
        final items = <(Chat, Message)>[
          for (final c in _chats)
            for (final m in c.messages)
              if (!m.deleted && m.kind == MsgKind.doc && (q.isEmpty || ((m.media?['name'] as String?) ?? '').toLowerCase().contains(q))) (c, m),
        ]..sort((a, b) => b.$2.time.compareTo(a.$2.time));
        if (items.isEmpty) return Center(child: Text('No documents', style: TextStyle(color: bc.muted)));
        return ListView(children: [
          for (final (c, m) in items)
            ListTile(
              leading: CircleAvatar(backgroundColor: bc.raised, child: Icon(Icons.description_outlined, color: bc.text)),
              title: Text((m.media?['name'] as String?) ?? 'Document', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${c.name} · ${_date(m.time)}', style: TextStyle(color: bc.muted, fontSize: 12.5)),
              onTap: () => _open(c, remember: false),
            ),
        ]);
    }
  }

  Widget _thumb(Message m, BaatlyColors bc) {
    final path = m.kind == MsgKind.image ? m.mediaPath : null;
    if (path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover, cacheWidth: 300, filterQuality: FilterQuality.low);
    }
    final t = m.media?['thumb'];
    if (t is String) {
      try {
        return Image.memory(base64Decode(t), fit: BoxFit.cover, gaplessPlayback: true);
      } catch (_) {}
    }
    return ColoredBox(color: bc.raised, child: Icon(m.kind == MsgKind.video ? Icons.videocam_outlined : Icons.photo_outlined, color: bc.muted));
  }
}
