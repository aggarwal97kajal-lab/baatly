import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_state.dart';
import '../../data/media.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/photo_viewer.dart';
import 'media_widgets.dart';

/// Search messages inside one chat.
class ChatSearchScreen extends StatefulWidget {
  final Chat chat;
  const ChatSearchScreen({super.key, required this.chat});
  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final q = _q.toLowerCase();
    final hits = q.isEmpty
        ? <Message>[]
        : widget.chat.messages.reversed
            .where((m) => !m.deleted && (m.text.toLowerCase().contains(q) || ((m.media?['name'] as String?) ?? '').toLowerCase().contains(q)))
            .toList();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _q = v.trim()),
          decoration: const InputDecoration(hintText: 'Search…', border: InputBorder.none),
        ),
      ),
      body: q.isEmpty
          ? Center(child: Text('Search messages in ${widget.chat.name}', style: TextStyle(color: bc.muted)))
          : hits.isEmpty
              ? Center(child: Text('No messages found', style: TextStyle(color: bc.muted)))
              : ListView.separated(
                  itemCount: hits.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: bc.line),
                  itemBuilder: (_, i) {
                    final m = hits[i];
                    final who = m.fromMe ? 'You' : (m.from != null ? Messenger.instance.nameFor(m.from!) : widget.chat.name);
                    final text = m.text.isNotEmpty ? m.text : ((m.media?['name'] as String?) ?? '');
                    final idx = text.toLowerCase().indexOf(q);
                    return ListTile(
                      title: Text(who, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      subtitle: idx < 0
                          ? Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)
                          : Text.rich(
                              TextSpan(children: [
                                TextSpan(text: text.substring(0, idx)),
                                TextSpan(text: text.substring(idx, idx + q.length), style: TextStyle(backgroundColor: context.primary.withOpacity(0.25), fontWeight: FontWeight.w700)),
                                TextSpan(text: text.substring(idx + q.length)),
                              ]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: Text(chatTime(m.time), style: TextStyle(fontSize: 11.5, color: bc.muted)),
                    );
                  },
                ),
    );
  }
}

/// Forward a message to one or more chats.
/// Pick chats, then run [send] for each.
Future<void> pickChatsAndSend(BuildContext context, void Function(Chat c) send) async {
  final picked = await Navigator.of(context).push<List<Chat>>(MaterialPageRoute(builder: (_) => _ForwardPicker()));
  if (picked == null || picked.isEmpty) return;
  for (final c in picked) {
    send(c);
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sent to ${picked.length} chat${picked.length == 1 ? '' : 's'}')));
  }
}

Future<void> forwardMessage(BuildContext context, Message m) async {
  final picked = await Navigator.of(context).push<List<Chat>>(MaterialPageRoute(builder: (_) => _ForwardPicker()));
  if (picked == null || picked.isEmpty) return;
  final ms = Messenger.instance;
  for (final c in picked) {
    if (m.kind == MsgKind.text) {
      ms.forwardText(c, m.text);
    } else if (const {MsgKind.image, MsgKind.voice, MsgKind.doc, MsgKind.video}.contains(m.kind) && m.mediaPath != null && File(m.mediaPath!).existsSync()) {
      ms.sendMedia(c, path: m.mediaPath!, kind: m.kind, caption: m.text, name: m.media?['name'] as String?, seconds: m.voiceSeconds, forwarded: true);
    } else if (m.media != null) {
      final md = Map<String, dynamic>.from(m.media!)..remove('votes');
      if (m.kind == MsgKind.poll) md['votes'] = <String, dynamic>{};
      ms.sendCard(c, m.kind, md, text: m.text, forwarded: true);
    }
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Forwarded to ${picked.length} chat${picked.length == 1 ? '' : 's'}')));
  }
}

class _ForwardPicker extends StatefulWidget {
  @override
  State<_ForwardPicker> createState() => _ForwardPickerState();
}

class _ForwardPickerState extends State<_ForwardPicker> {
  final _sel = <Chat>{};
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final chats = AppState.instance.chats.where((c) => (c.isReal || !AppState.instance.realChats) && !c.left).where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q.toLowerCase())).toList()
      ..sort((a, b) => (b.last?.time ?? DateTime(0)).compareTo(a.last?.time ?? DateTime(0)));
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          onChanged: (v) => setState(() => _q = v.trim()),
          decoration: const InputDecoration(hintText: 'Forward to…', border: InputBorder.none),
        ),
      ),
      floatingActionButton: _sel.isEmpty
          ? null
          : FloatingActionButton(
              backgroundColor: context.primary,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.pop(context, _sel.toList()),
              child: const Icon(Icons.send_rounded),
            ),
      body: ListView(children: [
        for (final c in chats)
          CheckboxListTile(
            value: _sel.contains(c),
            onChanged: (v) => setState(() => v == true ? _sel.add(c) : _sel.remove(c)),
            secondary: Avatar(initials: c.initials, colorIndex: c.colorIndex, photo: c.photo, size: 42),
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: c.isGroup ? Text('Group', style: TextStyle(color: bc.muted)) : null,
          ),
        const SizedBox(height: 90),
      ]),
    );
  }
}

/// Media, links and docs shared in a chat.
class ChatMediaScreen extends StatelessWidget {
  final Chat chat;
  const ChatMediaScreen({super.key, required this.chat});

  static final _url = RegExp(r'https?://[^\s]+', caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final media = chat.messages.reversed
        .where((m) => !m.deleted && (m.kind == MsgKind.image || m.kind == MsgKind.video) && m.media?['once'] != true)
        .toList();
    final docs = chat.messages.reversed.where((m) => !m.deleted && m.kind == MsgKind.doc).toList();
    final links = <(String, Message)>[
      for (final m in chat.messages.reversed)
        if (!m.deleted)
          for (final u in _url.allMatches(m.text)) (u.group(0)!, m),
    ];
    Widget empty(String t) => Center(child: Text(t, style: TextStyle(color: bc.muted)));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(chat.name),
          bottom: const TabBar(tabs: [Tab(text: 'Media'), Tab(text: 'Docs'), Tab(text: 'Links')]),
        ),
        body: TabBarView(children: [
          media.isEmpty
              ? empty('No media yet')
              : GridView.count(
                  crossAxisCount: 3,
                  padding: const EdgeInsets.all(2),
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                  children: [
                    for (final m in media)
                      GestureDetector(
                        onTap: () async {
                          final p = (m.mediaPath != null && File(m.mediaPath!).existsSync()) ? m.mediaPath : await Messenger.instance.downloadMedia(m);
                          if (p == null || !context.mounted) return;
                          if (m.kind == MsgKind.video) {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(path: p)));
                          } else {
                            PhotoViewerScreen.open(context, p, chat.name);
                          }
                        },
                        child: Container(
                          color: bc.raised,
                          child: m.kind == MsgKind.image && m.mediaPath != null && File(m.mediaPath!).existsSync()
                              ? Image.file(File(m.mediaPath!), fit: BoxFit.cover, cacheWidth: 300)
                              : Icon(m.kind == MsgKind.video ? Icons.play_circle_outline_rounded : Icons.photo_outlined, color: bc.muted, size: 34),
                        ),
                      ),
                  ],
                ),
          docs.isEmpty
              ? empty('No documents yet')
              : ListView(children: [
                  for (final m in docs)
                    ListTile(
                      leading: Icon(Icons.insert_drive_file_rounded, color: context.primary),
                      title: Text((m.media?['name'] as String?) ?? 'Document', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${MediaFiles.size((m.media?['size'] as int?) ?? 0)} · ${chatTime(m.time)}'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => Scaffold(appBar: AppBar(title: const Text('Document')), body: Center(child: DocContent(m: m, fg: bc.text))))),
                    ),
                ]),
          links.isEmpty
              ? empty('No links yet')
              : ListView(children: [
                  for (final l in links)
                    ListTile(
                      leading: Icon(Icons.link_rounded, color: context.primary),
                      title: Text(l.$1, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.primary)),
                      subtitle: Text(chatTime(l.$2.time)),
                      onTap: () => launchUrl(Uri.parse(l.$1), mode: LaunchMode.externalApplication),
                    ),
                ]),
        ]),
      ),
    );
  }
}
