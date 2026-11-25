import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../data/stickers.dart';
import '../home/status_tab.dart';
import 'chat_tools.dart';

/// WhatsApp-style full-screen photo from a chat: swipe between the chat's
/// photos, pinch to zoom, save / forward / add to status, ⋮ menu, reply bar.
class ChatPhotoScreen extends StatefulWidget {
  final Chat chat;
  final Message start;
  final void Function(Message m) onReply;
  const ChatPhotoScreen({super.key, required this.chat, required this.start, required this.onReply});

  static void open(BuildContext context, Chat chat, Message m, {required void Function(Message m) onReply}) {
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => ChatPhotoScreen(chat: chat, start: m, onReply: onReply),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  State<ChatPhotoScreen> createState() => _ChatPhotoScreenState();
}

class _ChatPhotoScreenState extends State<ChatPhotoScreen> {
  late final List<Message> _photos;
  late final PageController _page;
  int _i = 0;
  bool _chrome = true;

  @override
  void initState() {
    super.initState();
    _photos = widget.chat.messages
        .where((m) =>
            !m.deleted &&
            m.kind == MsgKind.image &&
            m.media?['once'] != true &&
            m.media?['stk'] != true &&
            m.mediaPath != null &&
            File(m.mediaPath!).existsSync())
        .toList();
    _i = _photos.indexWhere((m) => m.id == widget.start.id);
    if (_i < 0) {
      _photos.add(widget.start);
      _i = _photos.length - 1;
    }
    _page = PageController(initialPage: _i);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Message get _m => _photos[_i];
  String get _path => _m.mediaPath!;

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 2)));

  String get _who => _m.fromMe ? 'You' : (widget.chat.isRealGroup && _m.from != null ? Messenger.instance.nameFor(_m.from!) : widget.chat.name);

  String get _when {
    final t = _m.time;
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} minute${d.inMinutes == 1 ? '' : 's'} ago';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final hm = '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
    if (d.inDays < 1 && t.day == DateTime.now().day) return 'Today, $hm';
    return '${t.day}/${t.month}/${t.year}, $hm';
  }

  Future<void> _save() async {
    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImage(_path, album: 'BAATLY');
      _toast('Saved to gallery');
    } catch (_) {
      _toast("Couldn't save the photo");
    }
  }

  void _forward() => forwardMessage(context, _m);

  void _toStatus() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoStatusScreen(path: _path)));
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile(_path)]));
    } catch (_) {
      _toast("Couldn't share");
    }
  }

  Future<void> _edit() async {
    final c = await ImageCropper().cropImage(
      sourcePath: _path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Edit',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          statusBarLight: false,
          backgroundColor: Colors.black,
          lockAspectRatio: false,
        ),
      ],
    );
    if (c == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Send edited photo to ${widget.chat.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok == true && widget.chat.isReal) {
      Messenger.instance.sendMedia(widget.chat, path: c.path, kind: MsgKind.image, name: 'photo.jpg');
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _sticker() async {
    final cut = await StickerStore.cutOut(_path);
    if (cut == null) {
      _toast("Couldn't find a clear subject in this photo");
      return;
    }
    await StickerStore.instance.load();
    await StickerStore.instance.add(cut);
    _toast('Added to your stickers');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text('It will be deleted for you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete for me')),
        ],
      ),
    );
    if (ok != true) return;
    AppState.instance.deleteMessage(widget.chat, _m);
    if (mounted) Navigator.pop(context);
  }

  void _more() async {
    final v = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 80, 8, 0),
      items: const [
        PopupMenuItem(value: 'all', child: ListTile(leading: Icon(Icons.grid_view_rounded), title: Text('All media'))),
        PopupMenuItem(value: 'gallery', child: ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('View in gallery'))),
        PopupMenuItem(value: 'web', child: ListTile(leading: Icon(Icons.travel_explore_rounded), title: Text('Search on web'))),
        PopupMenuItem(value: 'rotate', child: ListTile(leading: Icon(Icons.rotate_left_rounded), title: Text('Rotate'))),
        PopupMenuItem(value: 'setas', child: ListTile(leading: Icon(Icons.wallpaper_rounded), title: Text('Set as…'))),
      ],
    );
    if (!mounted) return;
    switch (v) {
      case 'all':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatMediaScreen(chat: widget.chat)));
      case 'gallery':
      case 'setas':
        // The phone's own viewer has "Set as wallpaper / contact photo".
        final r = await OpenFilex.open(_path, type: 'image/*');
        if (r.type != ResultType.done) _toast('No gallery app found');
      case 'web':
        // Google Lens (or any app that can search images) from the share sheet.
        await SharePlus.instance.share(ShareParams(files: [XFile(_path)], text: 'Search this image'));
      case 'rotate':
        // Saved on the message, so the chat shows it rotated too (this phone only).
        final m = _m;
        final md = m.media ?? <String, dynamic>{};
        md['rot'] = (((md['rot'] as int?) ?? 0) + 1) % 4;
        m.media = md;
        AppState.instance.changed();
        setState(() {});
    }
  }

  void _menu() async {
    final v = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 80, 8, 0),
      items: [
        const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
        const PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.share_outlined), title: Text('Share'))),
        PopupMenuItem(value: 'star', child: ListTile(leading: Icon(_m.starred ? Icons.star_rounded : Icons.star_outline_rounded), title: Text(_m.starred ? 'Unstar' : 'Star'))),
        const PopupMenuItem(value: 'show', child: ListTile(leading: Icon(Icons.chat_outlined), title: Text('Show in chat'))),
        const PopupMenuItem(value: 'sticker', child: ListTile(leading: Icon(Icons.emoji_emotions_outlined), title: Text('Create sticker'))),
        const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Delete'))),
        const PopupMenuItem(value: 'more', child: ListTile(leading: SizedBox(), title: Text('More'), trailing: Icon(Icons.chevron_right_rounded))),
      ],
    );
    if (!mounted) return;
    switch (v) {
      case 'edit':
        await _edit();
      case 'share':
        await _share();
      case 'star':
        AppState.instance.toggleStar(_m);
        setState(() {});
        _toast(_m.starred ? 'Starred' : 'Unstarred');
      case 'show':
        Navigator.pop(context);
      case 'sticker':
        await _sticker();
      case 'delete':
        await _delete();
      case 'more':
        _more();
    }
  }

  void _react(String e) {
    AppState.instance.react(_m, e);
    setState(() {});
    _toast('Reacted $e');
  }

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        GestureDetector(
          onTap: () => setState(() => _chrome = !_chrome),
          child: PageView.builder(
            controller: _page,
            itemCount: _photos.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                // RotatedBox lays the photo out rotated, so it always fits the screen.
                child: RotatedBox(
                  quarterTurns: (_photos[i].media?['rot'] as int?) ?? 0,
                  child: Image.file(File(_photos[i].mediaPath!), fit: BoxFit.contain, filterQuality: FilterQuality.high),
                ),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          top: _chrome ? 0 : -120,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black54,
            child: SafeArea(
              bottom: false,
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: white)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_who, style: const TextStyle(color: white, fontSize: 17, fontWeight: FontWeight.w600)),
                    Text(_when, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                  ]),
                ),
                IconButton(tooltip: 'Save', onPressed: _save, icon: const Icon(Icons.download_rounded, color: white)),
                IconButton(tooltip: 'Forward', onPressed: _forward, icon: const Icon(Icons.shortcut_rounded, color: white)),
                IconButton(tooltip: 'Add to status', onPressed: _toStatus, icon: const Icon(Icons.add_a_photo_outlined, color: white)),
                IconButton(onPressed: _menu, icon: const Icon(Icons.more_vert_rounded, color: white)),
              ]),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          bottom: _chrome ? 0 : -140,
          left: 0,
          right: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Material(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(28),
                child: Row(children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () {
                        final m = _m;
                        Navigator.pop(context);
                        widget.onReply(m);
                      },
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(20, 14, 8, 14),
                        child: Text('Reply', style: TextStyle(color: Colors.white60, fontSize: 16)),
                      ),
                    ),
                  ),
                  for (final e in const ['❤️', '🙏'])
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _react(e),
                      child: Padding(padding: const EdgeInsets.all(8), child: Text(e, style: const TextStyle(fontSize: 24))),
                    ),
                  IconButton(
                    onPressed: () async {
                      final e = await showModalBottomSheet<String>(
                        context: context,
                        builder: (s) => SafeArea(
                          child: Wrap(alignment: WrapAlignment.center, children: [
                            for (final e in const ['❤️', '😂', '👍', '😮', '😢', '🙏', '🔥', '🎉', '😍', '👏', '😡', '🤔'])
                              InkWell(onTap: () => Navigator.pop(s, e), child: Padding(padding: const EdgeInsets.all(12), child: Text(e, style: const TextStyle(fontSize: 30)))),
                          ]),
                        ),
                      );
                      if (e != null) _react(e);
                    },
                    icon: const Icon(Icons.add_reaction_outlined, color: white),
                  ),
                  const SizedBox(width: 4),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
