import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'chat_info_screen.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  const ChatScreen({super.key, required this.chat});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  Message? _replyTo;

  Chat get chat => widget.chat;

  @override
  void initState() {
    super.initState();
    AppState.instance.activeChatId = chat.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Messenger.instance.openChat(chat);
    });
  }

  @override
  void dispose() {
    if (AppState.instance.activeChatId == chat.id) AppState.instance.activeChatId = null;
    Messenger.instance.closeChat(chat);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final full = _replyTo == null ? text : '↪ ${_replyTo!.text.split('\n').first}\n$text';
    _ctrl.clear();
    setState(() => _replyTo = null);
    AppState.instance.send(chat, full);
  }

  void _msgMenu(Message m) {
    HapticFeedback.selectionClick();
    final bc = context.bc;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final e in ['❤️', '😂', '👍', '😮', '🙏', '😢'])
                  GestureDetector(
                    onTap: () {
                      AppState.instance.react(m, e);
                      Navigator.pop(sheet);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: m.reaction == e ? context.primary.withOpacity(0.15) : bc.raised,
                        shape: BoxShape.circle,
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.reply_rounded),
            title: const Text('Reply'),
            onTap: () {
              Navigator.pop(sheet);
              setState(() => _replyTo = m);
            },
          ),
          ListTile(
            leading: Icon(m.starred ? Icons.star_rounded : Icons.star_outline_rounded),
            title: Text(m.starred ? 'Unstar' : 'Star'),
            onTap: () {
              AppState.instance.toggleStar(m);
              Navigator.pop(sheet);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('Copy'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: m.text));
              Navigator.pop(sheet);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
            title: Text('Delete for me', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () {
              AppState.instance.deleteMessage(chat, m);
              Navigator.pop(sheet);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatInfoScreen(chat: chat))),
          child: Row(children: [
            Hero(tag: 'av-${chat.id}', child: Avatar(initials: chat.initials, colorIndex: chat.colorIndex, photo: chat.photo, size: 38)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(chat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: bc.text)),
                ListenableBuilder(
                  listenable: AppState.instance,
                  builder: (context, _) => AnimatedSwitcher(
                    duration: Mitti.fast,
                    child: Text(
                      chat.typing
                          ? 'typing…'
                          : chat.isReal
                              ? ((chat.presence ?? '').isEmpty ? 'tap for contact info' : chat.presence!)
                              : (chat.isGroup ? chat.about : (chat.online ? 'online' : 'last seen today')),
                      key: ValueKey(chat.typing),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: chat.typing ? context.primary : bc.muted),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        actions: [
          IconButton(onPressed: () => showComingSoon(context, 'Video call'), icon: const Icon(Icons.videocam_outlined)),
          IconButton(onPressed: () => showComingSoon(context, 'Audio call'), icon: const Icon(Icons.call_outlined)),
        ],
      ),
      body: ChatBackground(
        child: Column(children: [
          Expanded(
            child: ListenableBuilder(
              listenable: AppState.instance,
              builder: (context, _) {
                final msgs = chat.messages.reversed.toList();
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  itemCount: msgs.length + 2,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return AnimatedSize(
                        duration: Mitti.fast,
                        child: chat.typing
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(color: bc.inBubble, borderRadius: BorderRadius.circular(18)),
                                  child: TypingDots(color: bc.muted),
                                ),
                              )
                            : const SizedBox.shrink(),
                      );
                    }
                    if (i == msgs.length + 1) {
                      return Column(children: [
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 30),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: bc.surface.withOpacity(0.92), borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            'Demo build: messages stay on this phone only. Encryption and real delivery come in the next milestone.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: bc.muted),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(12)),
                          child: Text('Today', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: bc.muted)),
                        ),
                        const SizedBox(height: 6),
                      ]);
                    }
                    final m = msgs[i - 1];
                    return _Bubble(key: ValueKey(m.id), m: m, onLongPress: () => _msgMenu(m));
                  },
                );
              },
            ),
          ),
          _Composer(
            ctrl: _ctrl,
            replyTo: _replyTo,
            onCancelReply: () => setState(() => _replyTo = null),
            onSend: _send,
            onChanged: () {
              setState(() {});
              if (_ctrl.text.isNotEmpty) Messenger.instance.typing(chat);
            },
          ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatefulWidget {
  final Message m;
  final VoidCallback onLongPress;
  const _Bubble({super.key, required this.m, required this.onLongPress});
  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  @override
  void initState() {
    super.initState();
    final fresh = DateTime.now().difference(widget.m.time).inSeconds < 2;
    if (fresh) {
      _a.forward();
    } else {
      _a.value = 1;
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final bc = context.bc;
    final me = m.fromMe;
    final bg = me ? bc.outBubble : bc.inBubble;
    final fg = me ? bc.onOutBubble : bc.text;
    final r = const Radius.circular(18);
    final radius = BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: me ? r : const Radius.circular(4),
      bottomRight: me ? const Radius.circular(4) : r,
    );

    Widget content;
    if (m.kind == MsgKind.voice) {
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: me ? Colors.white : context.primary, shape: BoxShape.circle),
          child: Icon(Icons.play_arrow_rounded, color: me ? context.primary : Colors.white),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 150, child: VoiceWave(color: fg)),
        const SizedBox(width: 6),
        Text('0:${m.voiceSeconds}', style: TextStyle(fontSize: 11, color: fg.withOpacity(0.8))),
      ]);
    } else {
      final lines = m.text.split('\n');
      final quoted = lines.first.startsWith('↪ ');
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (quoted)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            decoration: BoxDecoration(
              color: (me ? Colors.white : context.primary).withOpacity(me ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: me ? Colors.white : context.primary, width: 3)),
            ),
            child: Text(lines.first.substring(2), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg.withOpacity(0.85))),
          ),
        Text(quoted ? lines.skip(1).join('\n') : m.text, style: TextStyle(fontSize: 15, color: fg, height: 1.35)),
      ]);
    }

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
      margin: EdgeInsets.only(top: 4, bottom: m.reaction != null ? 14 : 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        boxShadow: me ? null : const [BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        content,
        const SizedBox(height: 3),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (m.starred) ...[Icon(Icons.star_rounded, size: 12, color: fg.withOpacity(0.7)), const SizedBox(width: 3)],
          if (m.expiresAt != null) ...[Icon(Icons.timer_outlined, size: 11, color: fg.withOpacity(0.7)), const SizedBox(width: 3)],
          Text(hhmm(m.time), style: TextStyle(fontSize: 10.5, color: fg.withOpacity(0.7))),
          if (me) ...[const SizedBox(width: 4), Ticks(status: m.status, color: Colors.white, readColor: kReadBlueOnBubble)],
        ]),
      ]),
    );

    final withReaction = m.reaction == null
        ? bubble
        : Stack(clipBehavior: Clip.none, children: [
            bubble,
            Positioned(
              bottom: 0,
              left: me ? null : 12,
              right: me ? 12 : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: bc.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: bc.line),
                ),
                child: Text(m.reaction!, style: const TextStyle(fontSize: 13)),
              ),
            ),
          ]);

    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween(begin: Offset(me ? 0.15 : -0.15, 0.25), end: Offset.zero).animate(CurvedAnimation(parent: _a, curve: Curves.easeOutCubic)),
        child: Align(
          alignment: me ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(onLongPress: widget.onLongPress, child: withReaction),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController ctrl;
  final Message? replyTo;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;
  final VoidCallback onChanged;
  const _Composer({required this.ctrl, required this.replyTo, required this.onCancelReply, required this.onSend, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final hasText = ctrl.text.trim().isNotEmpty;
    return Container(
      color: bc.surface,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (replyTo != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: bc.raised,
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: context.primary, width: 3)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(replyTo!.fromMe ? 'You' : 'Reply', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.primary)),
                    Text(replyTo!.kind == MsgKind.voice ? 'Voice note' : replyTo!.text.split('\n').last,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: bc.muted)),
                  ]),
                ),
                IconButton(onPressed: onCancelReply, icon: Icon(Icons.close_rounded, size: 18, color: bc.muted)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(24)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    IconButton(onPressed: () => showComingSoon(context, 'Emoji / stickers'), icon: Icon(Icons.emoji_emotions_outlined, color: bc.muted)),
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        minLines: 1,
                        maxLines: 5,
                        onChanged: (_) => onChanged(),
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(fontSize: 15, color: bc.text),
                        decoration: InputDecoration(
                          hintText: 'Message…',
                          hintStyle: TextStyle(color: bc.muted),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                    IconButton(onPressed: () => showComingSoon(context, 'Photo / document bhejna'), icon: Icon(Icons.attach_file_rounded, color: bc.muted)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: hasText ? onSend : () => showComingSoon(context, 'Voice note'),
                child: AnimatedContainer(
                  duration: Mitti.fast,
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(color: context.primary, shape: BoxShape.circle),
                  child: AnimatedSwitcher(
                    duration: Mitti.fast,
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Icon(hasText ? Icons.send_rounded : Icons.mic_rounded, key: ValueKey(hasText), color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
