import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/media.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chat_dialogs.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';
import '../chat/new_chat_screen.dart';

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});
  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  int _filter = 0;
  String _q = '';
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final s = AppState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        var list = s.chats.where((c) => c.archived == _showArchived).toList();
        if (_filter == 1) list = list.where((c) => c.unread > 0).toList();
        if (_filter == 2) list = list.where((c) => c.isGroup).toList();
        if (_filter == 3) list = list.where((c) => c.pinned).toList();
        if (_q.isNotEmpty) {
          final q = _q.toLowerCase();
          list = list.where((c) => c.name.toLowerCase().contains(q) || c.messages.any((m) => m.text.toLowerCase().contains(q))).toList();
        }
        list.sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return (b.last?.time ?? DateTime(0)).compareTo(a.last?.time ?? DateTime(0));
        });
        final unreadCount = s.chats.where((c) => c.unread > 0 && !c.archived).length;
        final archivedCount = s.chats.where((c) => c.archived).length;

        return Scaffold(
          backgroundColor: bc.bg,
          floatingActionButton: FloatingActionButton(
            backgroundColor: context.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewChatScreen())),
            child: const Icon(Icons.add_comment_rounded),
          ),
          body: SafeArea(
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
                  child: Row(children: [
                    if (_showArchived)
                      IconButton(onPressed: () => setState(() => _showArchived = false), icon: const Icon(Icons.arrow_back_rounded))
                    else
                      const BaatlyMark(size: 30),
                    const SizedBox(width: 8),
                    Text(_showArchived ? 'Archived' : 'BAATLY',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: _showArchived ? 0 : 1.5, color: bc.text)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => showComingSoon(context, 'Camera'),
                      icon: Icon(Icons.photo_camera_outlined, color: bc.text),
                    ),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    style: TextStyle(color: bc.text),
                    decoration: InputDecoration(
                      hintText: 'Search chats, people, messages',
                      hintStyle: TextStyle(color: bc.muted, fontSize: 14),
                      prefixIcon: Icon(Icons.search_rounded, color: bc.muted),
                      filled: true,
                      fillColor: bc.raised,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              if (!_showArchived)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      children: [
                        for (final (i, label) in ['All', 'Unread $unreadCount', 'Groups', 'Favourites'].indexed)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Pill(label: label, selected: _filter == i, onTap: () => setState(() => _filter = i)),
                          ),
                      ],
                    ),
                  ),
                ),
              if (!_showArchived && archivedCount > 0 && _q.isEmpty && _filter == 0)
                SliverToBoxAdapter(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: Icon(Icons.archive_outlined, color: bc.text),
                    title: Text('Archived', style: TextStyle(fontWeight: FontWeight.w700, color: bc.text)),
                    trailing: Text('$archivedCount', style: TextStyle(color: context.primary, fontWeight: FontWeight.w700)),
                    onTap: () => setState(() => _showArchived = true),
                  ),
                ),
              if (list.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.forum_outlined, size: 56, color: bc.muted.withOpacity(0.5)),
                      const SizedBox(height: 10),
                      Text(_q.isEmpty ? 'No chats here yet' : 'No results for "$_q"', style: TextStyle(color: bc.muted)),
                    ]),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => _ChatRow(chat: list[i]),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 90)),
            ]),
          ),
        );
      },
    );
  }
}

class _ChatRow extends StatelessWidget {
  final Chat chat;
  const _ChatRow({required this.chat});

  void _menu(BuildContext context) {
    final s = AppState.instance;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(chat.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
            title: Text(chat.pinned ? 'Unpin' : 'Pin'),
            onTap: () {
              s.toggle(() => chat.pinned = !chat.pinned);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: Icon(chat.muted ? Icons.volume_up_rounded : Icons.volume_off_rounded),
            title: Text(chat.muted ? 'Unmute' : 'Mute'),
            subtitle: chat.muted ? Text(muteLabel(chat)) : null,
            onTap: () {
              Navigator.pop(context);
              showMuteDialog(context, chat);
            },
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text(chat.archived ? 'Unarchive' : 'Archive'),
            onTap: () {
              s.toggle(() => chat.archived = !chat.archived);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.mark_chat_unread_outlined),
            title: const Text('Mark as unread'),
            onTap: () {
              s.toggle(() => chat.unread = chat.unread == 0 ? 1 : chat.unread);
              Navigator.pop(context);
            },
          ),
          if (!chat.isRealGroup || chat.left)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB3261E)),
              title: Text(chat.isRealGroup ? 'Delete group' : 'Delete chat', style: const TextStyle(color: Color(0xFFB3261E))),
              onTap: () async {
                Navigator.pop(context);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: Text(chat.isRealGroup ? 'Delete "${chat.name}"?' : 'Delete chat with ${chat.name}?'),
                    content: const Text('Messages will be removed from this phone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete', style: TextStyle(color: Color(0xFFB3261E)))),
                    ],
                  ),
                );
                if (ok == true) s.deleteChat(chat);
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final m = chat.last;
    final unread = chat.unread > 0;
    String preview = '';
    IconData? pIcon;
    if (m != null && m.deleted) {
      pIcon = Icons.block_rounded;
      preview = m.fromMe ? 'You deleted this message' : 'This message was deleted';
    } else if (m != null && m.kind == MsgKind.system) {
      preview = m.text;
    } else if (m != null && m.kind == MsgKind.poll) {
      pIcon = Icons.poll_rounded;
      preview = (m.media?['q'] as String?) ?? 'Poll';
    } else if (m != null && m.kind == MsgKind.location) {
      pIcon = Icons.location_on_rounded;
      preview = 'Location';
    } else if (m != null && m.kind == MsgKind.contact) {
      pIcon = Icons.person_rounded;
      preview = (m.media?['name'] as String?) ?? 'Contact';
    } else if (m != null && m.kind == MsgKind.event) {
      pIcon = Icons.event_rounded;
      preview = (m.media?['title'] as String?) ?? 'Event';
    } else if (m != null && m.kind == MsgKind.video) {
      pIcon = Icons.videocam_rounded;
      preview = m.text.trim().isEmpty ? 'Video' : m.text.replaceAll('\n', ' ');
    } else if (m != null && m.kind == MsgKind.image && m.media?['once'] == true) {
      pIcon = Icons.looks_one_outlined;
      preview = 'Photo';
    } else if (m != null) {
      if (m.kind == MsgKind.image) {
        pIcon = Icons.photo_camera_rounded;
        preview = m.text.trim().isEmpty ? 'Photo' : m.text.replaceAll('\n', ' ');
      } else if (m.kind == MsgKind.doc) {
        pIcon = Icons.insert_drive_file_rounded;
        preview = (m.media?['name'] as String?) ?? 'Document';
      } else if (m.kind == MsgKind.voice) {
        pIcon = Icons.mic_rounded;
        preview = 'Voice message · ${MediaFiles.fmtDur(m.voiceSeconds)}';
      } else {
        preview = m.text.replaceAll('\n', ' ');
      }
    }
    if (m != null && chat.isGroup && m.from != null && !m.fromMe && m.kind != MsgKind.system && !m.deleted) {
      preview = '${Messenger.instance.nameFor(m.from!)}: $preview';
    }
    return InkWell(
      onTap: () {
        AppState.instance.openChat(chat);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
      },
      onLongPress: () => _menu(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showProfilePeek(context, chat),
            child: Hero(tag: 'av-${chat.id}', child: Avatar(initials: chat.initials, colorIndex: chat.colorIndex, photo: chat.photo, size: 52, online: chat.online)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(chat.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: bc.text)),
                ),
                Text(m == null ? '' : chatTime(m.time),
                    style: TextStyle(fontSize: 12, color: unread ? context.primary : bc.muted, fontWeight: unread ? FontWeight.w700 : FontWeight.w400)),
              ]),
              const SizedBox(height: 3),
              if (chat.typing)
                Text(chat.typingName != null ? '${chat.typingName} is typing…' : 'typing…', style: TextStyle(fontSize: 13, color: context.primary, fontWeight: FontWeight.w700))
              else
              Row(children: [
                if (m != null && m.fromMe) ...[Ticks(status: m.status, color: bc.muted), const SizedBox(width: 3)],
                if (pIcon != null) ...[Icon(pIcon, size: 15, color: context.primary), const SizedBox(width: 3)],
                Expanded(
                  child: Text(preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: unread ? bc.text : bc.muted, fontWeight: unread ? FontWeight.w500 : FontWeight.w400)),
                ),
                if (chat.muted) Icon(Icons.volume_off_rounded, size: 16, color: bc.muted),
                if (chat.pinned) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.push_pin_rounded, size: 15, color: bc.muted)),
                if (unread)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: chat.muted ? bc.muted : context.primary, borderRadius: BorderRadius.circular(10)),
                    child: Text('${chat.unread}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
