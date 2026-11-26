import '../../widgets/photo_viewer.dart';
import 'shared_cards.dart';
import '../settings/quick_replies.dart';
import '../../data/secure_screen.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/palettes.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'chat_info_screen.dart';
import 'media_widgets.dart';
import 'cards.dart';
import 'group_screens.dart';
import 'chat_tools.dart';
import 'location.dart';
import 'gif_panel.dart';
import 'links.dart';
import 'photo_screen.dart';
import 'camera_screen.dart';
import 'safety_screens.dart';
import 'message_tools.dart';
import 'broadcast.dart';
import 'translate_ui.dart';
import '../../data/translate.dart';
import '../../data/calls.dart';
import '../../data/group_calls.dart';
import '../../data/media.dart';
import '../../data/stickers.dart';
import 'package:image_cropper/image_cropper.dart';

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
  // WhatsApp-style selection: long-press a message.
  final Set<String> _sel = {};
  OverlayEntry? _reactBar;
  Message? _editing;

  List<Message> get _selMsgs => chat.messages.where((m) => _sel.contains(m.id)).toList();

  bool _canEdit(Message m) =>
      m.fromMe && !m.deleted && m.kind == MsgKind.text && DateTime.now().difference(m.time).inMinutes < 5;

  void _hideReactBar() {
    _reactBar?.remove();
    _reactBar = null;
  }

  void _clearSel() {
    _hideReactBar();
    if (_sel.isNotEmpty) setState(() => _sel.clear());
  }

  void _onLongPress(Message m, BuildContext bubble) {
    if (m.kind == MsgKind.system || m.kind == MsgKind.call) return;
    HapticFeedback.mediumImpact();
    setState(() => _sel.add(m.id));
    _hideReactBar();
    if (_sel.length == 1 && !m.deleted) _showReactBar(m, bubble);
  }

  void _onTapMsg(Message m) {
    if (_sel.isEmpty) return;
    _hideReactBar();
    setState(() => _sel.contains(m.id) ? _sel.remove(m.id) : _sel.add(m.id));
  }

  void _showReactBar(Message m, BuildContext bubble) {
    final box = bubble.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final pos = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.of(context).size;
    final top = pos.dy - 58 < 110 ? pos.dy + box.size.height + 6 : pos.dy - 58;
    final bc = context.bc;
    _reactBar = OverlayEntry(
      builder: (_) => Positioned(
        top: top,
        left: m.fromMe ? null : 10,
        right: m.fromMe ? 10 : null,
        child: Material(
          color: bc.surface,
          elevation: 8,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final e in const ['👍', '❤️', '😂', '😮', '😢', '🙏'])
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    AppState.instance.react(m, e);
                    _clearSel();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: m.reaction == e ? context.primary.withOpacity(0.2) : null),
                    child: Text(e, style: TextStyle(fontSize: screen.width < 360 ? 22 : 26)),
                  ),
                ),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () async {
                  _hideReactBar();
                  final e = await showModalBottomSheet<String>(
                    context: context,
                    builder: (s) => SafeArea(
                      child: SizedBox(
                        height: 320,
                        child: EmojiPicker(
                          onEmojiSelected: (_, em) => Navigator.pop(s, em.emoji),
                          config: Config(
                            height: 320,
                            emojiViewConfig: EmojiViewConfig(backgroundColor: bc.bg, columns: 8, emojiSizeMax: 28),
                            categoryViewConfig: CategoryViewConfig(backgroundColor: bc.surface, indicatorColor: context.primary, iconColorSelected: context.primary),
                            bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
                          ),
                        ),
                      ),
                    ),
                  );
                  if (e != null) AppState.instance.react(m, e);
                  _clearSel();
                },
                child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.add_rounded, color: bc.muted)),
              ),
            ]),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_reactBar!);
  }

  void _startEdit(Message m) {
    _clearSel();
    final lines = m.text.split('\n');
    final body = lines.first.startsWith('↪ ') ? lines.skip(1).join('\n') : m.text;
    setState(() {
      _editing = m;
      _replyTo = null;
    });
    _ctrl.text = body;
    _ctrl.selection = TextSelection.collapsed(offset: body.length);
    _focus.requestFocus();
  }

  Future<void> _deleteSelected() async {
    final ms = _selMsgs;
    if (ms.isEmpty) return;
    final everyone = ms.every((m) => m.fromMe && !m.deleted && DateTime.now().difference(m.time).inMinutes < 5);
    final r = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(ms.length == 1 ? 'Delete message?' : 'Delete ${ms.length} messages?'),
        actions: [
          if (everyone) TextButton(onPressed: () => Navigator.pop(d, 'all'), child: const Text('Delete for everyone')),
          TextButton(onPressed: () => Navigator.pop(d, 'me'), child: const Text('Delete for me')),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        ],
      ),
    );
    if (r == null) return;
    for (final m in ms) {
      if (r == 'all') {
        Messenger.instance.deleteForEveryone(chat, m);
      } else {
        AppState.instance.deleteMessage(chat, m);
      }
    }
    _clearSel();
  }

  Future<void> _forwardSelected() async {
    final ms = _selMsgs.where((m) => !m.deleted).toList();
    _clearSel();
    if (ms.length == 1) {
      await forwardMessage(context, ms.first);
    } else if (ms.isNotEmpty) {
      await forwardMany(context, ms);
    }
  }

  PreferredSizeWidget _selectionBar() {
    final ms = _selMsgs;
    final one = ms.length == 1 ? ms.first : null;
    final allStarred = ms.isNotEmpty && ms.every((m) => m.starred);
    return AppBar(
      leading: IconButton(onPressed: _clearSel, icon: const Icon(Icons.arrow_back_rounded)),
      title: Text('${ms.length}'),
      actions: [
        if (one != null && !one.deleted)
          IconButton(
            tooltip: 'Reply',
            onPressed: () {
              _clearSel();
              setState(() {
                _replyTo = one;
                _editing = null;
              });
              _focus.requestFocus();
            },
            icon: const Icon(Icons.reply_rounded),
          ),
        if (one != null && _canEdit(one)) IconButton(tooltip: 'Edit', onPressed: () => _startEdit(one), icon: const Icon(Icons.edit_outlined)),
        IconButton(
          tooltip: allStarred ? 'Unstar' : 'Star',
          onPressed: () {
            for (final m in ms) {
              if (m.starred == allStarred) AppState.instance.toggleStar(m);
            }
            _clearSel();
          },
          icon: Icon(allStarred ? Icons.star_rounded : Icons.star_outline_rounded),
        ),
        IconButton(tooltip: 'Delete', onPressed: _deleteSelected, icon: const Icon(Icons.delete_outline_rounded)),
        if (ms.any((m) => !m.deleted)) IconButton(tooltip: 'Forward', onPressed: _forwardSelected, icon: const Icon(Icons.shortcut_rounded)),
        PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'copy':
                await Clipboard.setData(ClipboardData(text: ms.map((m) => m.text).where((t) => t.isNotEmpty).join('\n')));
                _toast(ms.length == 1 ? 'Message copied' : 'Messages copied');
              case 'pin':
                Messenger.instance.pin(chat, chat.pinnedId == one!.id ? null : one);
              case 'sticker':
                await StickerStore.instance.load();
                await StickerStore.instance.add(one!.mediaPath!);
                _toast('Added to your stickers');
              case 'info':
                _clearSel();
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MessageInfoScreen(chat: chat, m: one!, bubble: _InfoBubble(m: one!))));
                return;
              case 'remind':
                _clearSel();
                await remindMe(context, chat, one!);
                return;
              case 'unremind':
                await Messenger.instance.clearReminder(one!);
              case 'translate':
                _clearSel();
                await translateMessage(context, chat, one!);
                return;
              case 'untranslate':
                one!.media?.remove('tr');
                AppState.instance.changed();
              case 'select':
                setState(() => _sel.addAll(chat.messages.where((m) => m.kind != MsgKind.system && m.kind != MsgKind.call).map((m) => m.id)));
                _hideReactBar();
                return;
            }
            _clearSel();
          },
          itemBuilder: (_) => [
            if (ms.any((m) => m.text.trim().isNotEmpty && !m.deleted)) const PopupMenuItem(value: 'copy', child: Text('Copy')),
            if (one != null && !one.deleted && (!chat.isRealGroup || Messenger.instance.canEditGroup(chat)))
              PopupMenuItem(value: 'pin', child: Text(chat.pinnedId == one.id ? 'Unpin' : 'Pin')),
            if (one != null && one.media?['stk'] == true && one.mediaPath != null && File(one.mediaPath!).existsSync())
              const PopupMenuItem(value: 'sticker', child: Text('Add to my stickers')),
            if (one != null && one.fromMe && !one.deleted && chat.isReal && !chat.isNotes && !chat.isBroadcast && one.media?['sched'] == null)
              const PopupMenuItem(value: 'info', child: Text('Info')),
            if (one != null && !one.deleted && chat.isReal && one.media?['sched'] == null)
              Messenger.instance.reminders.containsKey(one.id)
                  ? const PopupMenuItem(value: 'unremind', child: Text('Remove reminder'))
                  : const PopupMenuItem(value: 'remind', child: Text('Remind me')),
            if (one != null && !one.deleted && one.kind == MsgKind.text && one.text.trim().isNotEmpty)
              one.media?['tr'] != null
                  ? const PopupMenuItem(value: 'untranslate', child: Text('Hide translation'))
                  : const PopupMenuItem(value: 'translate', child: Text('Translate')),
            const PopupMenuItem(value: 'select', child: Text('Select all')),
          ],
        ),
      ],
    );
  }
  Map<String, dynamic>? _lp; // link preview for the text being typed
  String? _lpFor, _lpOff;
  Timer? _lpTimer;

  void _watchLink() {
    final url = firstUrl(_ctrl.text);
    if (url == null) {
      if (_lp != null || _lpFor != null) setState(() => _lp = _lpFor = null);
      return;
    }
    if (url == _lpFor || url == _lpOff) return;
    _lpFor = url;
    _lp = null;
    _lpTimer?.cancel();
    _lpTimer = Timer(const Duration(milliseconds: 500), () async {
      final p = await fetchLinkPreview(url);
      if (!mounted || _lpFor != url) return;
      setState(() => _lp = p);
    });
  }
  final _rec = AudioRecorder();
  bool _recording = false; // mic is live (holding or locked)
  bool _recLocked = false; // slid up: hands-free
  bool _recPaused = false;
  bool _holding = false; // finger is still on the mic
  Offset _drag = Offset.zero; // finger travel while holding
  DateTime? _recStart; // start of the current (unpaused) stretch
  Duration _recAccum = Duration.zero; // time recorded before the last pause
  Future<void>? _recStarting;
  Timer? _recTimer;
  StreamSubscription<Amplitude>? _ampSub;
  final List<double> _amps = [];
  String? _recPath;
  bool _emoji = false;
  int _panel = 0; // 0 emoji, 1 stickers, 2 GIF
  bool _emojiSearch = false;
  final _focus = FocusNode();

  Chat get chat => widget.chat;

  void _toast(String t, {Duration duration = const Duration(seconds: 3)}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar(); // never queue up behind an old one
    m.showSnackBar(SnackBar(content: Text(t), duration: duration));
  }

  void _sendMedia(String path, MsgKind kind, {String caption = '', String? name, int seconds = 0, bool once = false}) {
    if (chat.isReal) {
      Messenger.instance.sendMedia(chat, path: path, kind: kind, caption: caption, name: name, seconds: seconds, once: once);
    } else {
      final s = AppState.instance;
      chat.messages.add(Message(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: caption,
        fromMe: true,
        time: DateTime.now(),
        kind: kind,
        voiceSeconds: seconds,
        mediaPath: path,
        media: {'name': name ?? path.split('/').last, 'type': kind.name},
      ));
      s.changed();
    }
  }

  /// Copies a picked file into BAATLY's own folder (pickers use temp files).
  Future<String> _keep(String src, String name) async {
    final dir = await MediaFiles.dir();
    final safe = name.replaceAll(RegExp(r'[^\w.\- ]'), '_');
    final dest = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$safe');
    await File(src).copy(dest.path);
    return dest.path;
  }

  Future<void> _pickImage(ImageSource src) async {
    XFile? f;
    try {
      final hd = AppState.instance.hdPhotos;
      f = await ImagePicker().pickImage(source: src, maxWidth: hd ? 4096 : 1600, imageQuality: hd ? 95 : 80);
    } catch (_) {
      _toast('Camera / photos permission needed');
      return;
    }
    if (f == null || !mounted) return;
    final r = await Navigator.of(context).push<(String, bool)>(MaterialPageRoute(builder: (_) => SendPhotoScreen(path: f!.path, to: chat.name)));
    if (r == null) return;
    final kept = await _keep(f.path, f.name.isEmpty ? 'photo.jpg' : f.name);
    _sendMedia(kept, MsgKind.image, caption: r.$1, name: 'photo.jpg', once: r.$2);
  }

  void _sendSticker(String path) {
    if (chat.isReal) {
      Messenger.instance.sendMedia(chat, path: path, kind: MsgKind.image, name: 'sticker.png', extra: {'stk': true});
    } else {
      _sendMedia(path, MsgKind.image, name: 'sticker.png');
    }
  }

  void _sendKlipy(String path, {required bool sticker}) {
    if (sticker) {
      _sendSticker(path);
    } else if (chat.isReal) {
      Messenger.instance.sendMedia(chat, path: path, kind: MsgKind.image, name: 'anim.gif', extra: {'gif': true});
    } else {
      _sendMedia(path, MsgKind.image, name: 'anim.gif');
    }
  }

  Future<void> _createSticker() async {
    XFile? f;
    try {
      f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600);
    } catch (_) {
      _toast('Photos permission needed');
      return;
    }
    if (f == null || !mounted) return;
    // Like WhatsApp: cut the subject out of the photo automatically.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 16),
          Expanded(child: Text('Removing background…')),
        ]),
      ),
    );
    final cut = await StickerStore.cutOut(f.path);
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (cut != null) {
      await StickerStore.instance.add(cut);
      _toast('Added to your stickers');
      return;
    }
    _toast("Couldn't find a clear subject. Crop the photo instead.");
    CroppedFile? c;
    try {
      c = await ImageCropper().cropImage(
        sourcePath: f.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 512,
        maxHeight: 512,
        compressFormat: ImageCompressFormat.png,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Make a sticker',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            statusBarLight: false,
            backgroundColor: Colors.black,
            lockAspectRatio: true,
          ),
        ],
      );
    } catch (_) {}
    if (c == null) return;
    await StickerStore.instance.add(c.path);
    _toast('Added to your stickers');
  }

  Future<void> _pickGif() async {
    FilePickerResult? r;
    try {
      r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['gif']);
    } catch (_) {
      _toast('Storage permission needed');
      return;
    }
    final f = r?.files.single;
    if (f?.path == null) return;
    if ((f!.size) > 16 * 1024 * 1024) {
      _toast('This GIF is too large');
      return;
    }
    final kept = await _keep(f.path!, 'anim.gif');
    if (chat.isReal) {
      Messenger.instance.sendMedia(chat, path: kept, kind: MsgKind.image, name: 'anim.gif', extra: {'gif': true});
    } else {
      _sendMedia(kept, MsgKind.image, name: 'anim.gif');
    }
    setState(() => _emoji = false);
  }

  Future<void> _pickVideo() async {
    XFile? f;
    try {
      f = await ImagePicker().pickVideo(source: ImageSource.gallery);
    } catch (_) {
      _toast('Photos permission needed');
      return;
    }
    if (f == null) return;
    await _sendVideoPath(f.path, f.name);
  }

  Future<void> _openCamera() async {
    final shots = await CameraScreen.open(context, chat.name);
    if (shots == null) return;
    for (final s in shots) {
      if (s.video) {
        await _sendVideoPath(s.path, 'video.mp4', note: s.note, caption: s.caption);
      } else {
        final kept = await _keep(s.path, s.path.toLowerCase().endsWith('.png') ? 'photo.png' : 'photo.jpg');
        _sendMedia(kept, MsgKind.image, caption: s.caption, name: 'photo.jpg', once: s.once);
      }
    }
  }

  Future<void> _sendVideoPath(String path, String pickedName, {bool note = false, String caption = ''}) async {
    final f = XFile(path, name: pickedName);
    final size = await File(f.path).length();
    if (size > 500 * 1024 * 1024) {
      _toast('This video is too large');
      return;
    }
    int secs = 0;
    try {
      final c = VideoPlayerController.file(File(f.path));
      await c.initialize();
      secs = c.value.duration.inSeconds;
      await c.dispose();
    } catch (_) {}
    // Compress like WhatsApp (~720p) and grab a preview frame.
    var src = f.path;
    String? thumb;
    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 18), Text('Preparing video…')])),
      );
    }
    try {
      final frame = await VideoCompress.getByteThumbnail(f.path, quality: 60, position: -1);
      if (frame != null) thumb = await MediaFiles.thumbFromBytes(frame);
      final info = await VideoCompress.compressVideo(f.path, quality: VideoQuality.Res1280x720Quality, deleteOrigin: false, includeAudio: true);
      if (info?.path != null && (info!.filesize ?? size) < size) src = info.path!;
    } catch (_) {
      // Fall back to the original file.
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    final finalSize = await File(src).length();
    if (finalSize > 64 * 1024 * 1024) {
      _toast('Videos up to 64 MB can be sent');
      return;
    }
    final name = f.name.isEmpty ? 'video.mp4' : f.name;
    final kept = await _keep(src, name.toLowerCase().endsWith('.mp4') ? name : '$name.mp4');
    if (chat.isReal) {
      Messenger.instance.sendMedia(chat, path: kept, kind: MsgKind.video, caption: caption, name: name, seconds: secs, extra: {if (thumb != null) 'thumb': thumb, if (note) 'note': true});
    } else {
      _sendMedia(kept, MsgKind.video, name: name, seconds: secs);
    }
  }

  Future<void> _pickAudio() async {
    FilePickerResult? r;
    try {
      r = await FilePicker.platform.pickFiles(type: FileType.audio);
    } catch (_) {
      _toast("Couldn't open audio files");
      return;
    }
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    if (f.size > 64 * 1024 * 1024) {
      _toast('Audio up to 64 MB can be sent');
      return;
    }
    var secs = 0;
    try {
      final p = AudioPlayer();
      secs = (await p.setFilePath(f.path!))?.inSeconds ?? 0;
      await p.dispose();
    } catch (_) {}
    final kept = await _keep(f.path!, f.name);
    if (chat.isReal) {
      Messenger.instance.sendMedia(chat, path: kept, kind: MsgKind.voice, name: f.name, seconds: secs, extra: {'audio': true});
    } else {
      _sendMedia(kept, MsgKind.voice, name: f.name, seconds: secs);
    }
  }

  Future<void> _pickDoc() async {
    FilePickerResult? r;
    try {
      // Documents first; the picker still lets you browse to any other file.
      r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf', 'doc', 'docx', 'xls', 'xlsx', 'csv', 'ppt', 'pptx', 'txt', 'rtf', 'odt', 'ods', 'odp',
          'zip', 'rar', '7z', 'apk', 'epub', 'json', 'xml', 'html',
          // Audio files too (they play right in the chat).
          'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac', 'amr',
        ],
      );
    } catch (_) {
      _toast("Couldn't open files");
      return;
    }
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    if (f.size > 64 * 1024 * 1024) {
      _toast('Files up to 64 MB can be sent');
      return;
    }
    final kept = await _keep(f.path!, f.name);
    _sendMedia(kept, MsgKind.doc, name: f.name);
  }

  Future<void> _card(Widget screen) async {
    final md = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => screen));
    if (md == null) return;
    Messenger.instance.sendCard(chat, Messenger.kindOf(md['type'] as String?), md);
  }

  Future<void> _sendLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('Turn on location (GPS) first');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _toast('Allow location to share it');
        return;
      }
      _toast('Getting your location…');
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Send your current location?'),
          content: Text('Accurate to about ${pos.accuracy.round()} m'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Send')),
          ],
        ),
      );
      if (ok == true) Messenger.instance.sendCard(chat, MsgKind.location, {'type': 'location', 'lat': pos.latitude, 'lng': pos.longitude});
    } catch (e) {
      _toast("Couldn't get location ($e)");
    }
  }

  void _attach() {
    final bc = context.bc;
    Widget item(IconData i, String label, Color c, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 27, backgroundColor: c, child: Icon(i, color: Colors.white)),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(fontSize: 12.5, color: bc.text)),
            ]),
          ),
        );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              item(Icons.photo_library_rounded, 'Gallery', const Color(0xFF2E7D8C), () => _pickImage(ImageSource.gallery)),
              item(Icons.photo_camera_rounded, 'Camera', const Color(0xFFC8553D), _openCamera),
              item(Icons.location_on_rounded, 'Location', const Color(0xFF2E7D5B), () async {
                final md = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const SendLocationScreen()));
                if (md == null) return;
                if (md['live'] == true) {
                  Messenger.instance.shareLive(chat, md);
                } else {
                  Messenger.instance.sendCard(chat, MsgKind.location, md);
                }
              }),
              item(Icons.person_rounded, 'Contact', const Color(0xFF3D7DC8), () => _card(const ShareContactScreen())),
              item(Icons.insert_drive_file_rounded, 'Document', const Color(0xFF7A5BA6), _pickDoc),
              item(Icons.poll_rounded, 'Poll', const Color(0xFFE0A100), () => _card(const PollCreateScreen())),
              item(Icons.event_rounded, 'Event', const Color(0xFFD9467A), () => _card(const EventCreateScreen())),
              item(Icons.videocam_rounded, 'Video', const Color(0xFF3A8F6B), _pickVideo),
              if (!chat.isBroadcast) item(Icons.checklist_rounded, 'Checklist', const Color(0xFFC8553D), () => _card(const ChecklistCreateScreen())),
              if (!chat.isBroadcast && !chat.isNotes) item(Icons.currency_rupee_rounded, 'Hisaab', const Color(0xFF00897B), () => _card(const LedgerCreateScreen())),
            ],
          ),
        ),
      ),
    );
  }

  Duration get _recElapsed =>
      _recAccum + (_recStart == null || _recPaused ? Duration.zero : DateTime.now().difference(_recStart!));

  // Finger goes down on the mic: start straight away, like WhatsApp.
  void _micDown() {
    if (_recording || _recStarting != null) return;
    _holding = true;
    _drag = Offset.zero;
    _recStarting = _startRecording().whenComplete(() => _recStarting = null);
  }

  void _micMove(Offset delta) {
    if (!_holding || _recLocked) return;
    _drag += delta;
    if (_drag.dx < -110) {
      _holding = false;
      HapticFeedback.lightImpact();
      _stopRecording(send: false);
      return;
    }
    if (_drag.dy < -90) {
      HapticFeedback.mediumImpact();
      setState(() {
        _recLocked = true;
        _holding = false;
        _drag = Offset.zero;
      });
      return;
    }
    setState(() {});
  }

  Future<void> _micUp({bool cancelled = false}) async {
    if (!_holding) return;
    _holding = false;
    await _recStarting;
    if (!_recording || _recLocked) return;
    if (cancelled) {
      _stopRecording(send: false);
    } else if (_recElapsed.inMilliseconds < 700) {
      _stopRecording(send: false);
      _toast('Hold to record, release to send', duration: const Duration(milliseconds: 1200));
    } else {
      _stopRecording(send: true);
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _rec.hasPermission()) {
        _holding = false;
        _toast('Allow microphone to record voice notes');
        return;
      }
      if (!_holding) return; // let go while the permission box was up
      final dir = await MediaFiles.dir();
      _recPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      // Mono speech quality: a quarter of the old size, so it uploads much faster.
      await _rec.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 22050, numChannels: 1),
          path: _recPath!);
      HapticFeedback.mediumImpact();
      _amps.clear();
      _ampSub = _rec.onAmplitudeChanged(const Duration(milliseconds: 90)).listen((a) {
        if (_recPaused) return;
        final v = ((a.current + 50) / 50).clamp(0.06, 1.0).toDouble();
        _amps.add(v);
        if (_amps.length > 200) _amps.removeAt(0);
        if (mounted) setState(() {});
      });
      setState(() {
        _recording = true;
        _recLocked = false;
        _recPaused = false;
        _recAccum = Duration.zero;
        _recStart = DateTime.now();
      });
      _recTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => mounted ? setState(() {}) : null);
    } catch (e) {
      _holding = false;
      _toast("Couldn't start recording ($e)");
    }
  }

  Future<void> _togglePause() async {
    try {
      if (_recPaused) {
        await _rec.resume();
        setState(() {
          _recPaused = false;
          _recStart = DateTime.now();
        });
      } else {
        await _rec.pause();
        setState(() {
          _recAccum = _recElapsed;
          _recPaused = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _stopRecording({required bool send}) async {
    _recTimer?.cancel();
    _ampSub?.cancel();
    _ampSub = null;
    final secs = _recElapsed.inMilliseconds / 1000;
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _recording = false;
        _recLocked = false;
        _recPaused = false;
        _holding = false;
        _drag = Offset.zero;
        _recStart = null;
        _recAccum = Duration.zero;
      });
    }
    path ??= _recPath;
    if (path == null) return;
    if (!send || secs < 0.7) {
      try {
        await File(path).delete();
      } catch (_) {}
      return;
    }
    _sendMedia(path, MsgKind.voice, name: 'voice.m4a', seconds: secs.round().clamp(1, 1 << 30));
  }

  @override
  void initState() {
    super.initState();
    AppState.instance.activeChatId = chat.id;
    _secure = chat.locked && AppState.instance.shotBlockLocked;
    if (_secure) SecureScreen.hold();
    final d = chat.draft;
    if (d != null && d.isNotEmpty) {
      _ctrl.text = d;
      _ctrl.selection = TextSelection.collapsed(offset: d.length);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Messenger.instance.openChat(chat);
    });
    AppState.instance.addListener(_autoTranslate);
    _autoTranslate();
  }

  final Set<String> _trying = {};
  bool _translating = false;

  /// "Auto-translate this chat": translate their new text messages on this phone.
  Future<void> _autoTranslate() async {
    final to = chat.autoTranslate;
    if (to == null || _translating || !mounted) return;
    final todo = chat.messages.reversed
        .where((m) => !m.fromMe && !m.deleted && m.kind == MsgKind.text && m.text.trim().isNotEmpty && m.media?['tr'] == null && !_trying.contains(m.id))
        .take(30)
        .toList();
    if (todo.isEmpty) return;
    _translating = true;
    try {
      for (final m in todo) {
        _trying.add(m.id);
        try {
          final r = await Translate.instance.run(m.text, to: to);
          if (r.from == to) continue;
          (m.media ??= {})['tr'] = {'to': to, 'from': r.from, 't': r.text};
        } catch (_) {}
      }
      if (mounted) AppState.instance.changed();
    } finally {
      _translating = false;
    }
  }

  /// Keep what was typed but not sent as a draft (shown in the chat list).
  void _saveDraft() {
    final t = _editing != null ? '' : _ctrl.text.trim();
    final old = chat.draft;
    if (t.isEmpty) {
      if (old == null) return;
      chat.draft = null;
      chat.draftAt = null;
    } else {
      if (t == old) return;
      chat.draft = t;
      chat.draftAt = DateTime.now();
    }
    Messenger.instance.saveSoon();
    AppState.instance.changed();
  }

  bool _secure = false;

  @override
  void dispose() {
    if (_secure) SecureScreen.release();
    _saveDraft();
    AppState.instance.removeListener(_autoTranslate);
    if (AppState.instance.activeChatId == chat.id) AppState.instance.activeChatId = null;
    Messenger.instance.closeChat(chat);
    _hideReactBar();
    _recTimer?.cancel();
    _lpTimer?.cancel();
    _ampSub?.cancel();
    _rec.dispose();
    _focus.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final ed = _editing;
    if (ed != null) {
      final lines = ed.text.split('\n');
      final full = lines.first.startsWith('↪ ') ? '${lines.first}\n$text' : text;
      _ctrl.clear();
      setState(() => _editing = null);
      if (full != ed.text) Messenger.instance.editMessage(chat, ed, full);
      return;
    }
    final full = _replyTo == null ? text : '↪ ${_replyTo!.text.split('\n').first}\n$text';
    final lp = _lp != null && firstUrl(text) == _lp!['u'] ? _lp : null;
    _ctrl.clear();
    _lpTimer?.cancel();
    setState(() {
      _replyTo = null;
      _lp = _lpFor = _lpOff = null;
    });
    final to = chat.sendTranslate;
    if (to != null && chat.isReal) {
      // "Translate what I send": they get it in their language, I see what I wrote under it.
      Translate.instance.run(text, to: to).then((r) {
        final out = _replyTo == null && !full.startsWith('↪ ') ? r.text : '${full.split('\n').first}\n${r.text}';
        Messenger.instance.send(chat, out, extra: r.from == to ? null : {'orig': text});
      }).catchError((Object e) {
        _toast(e is TranslateError ? '${e.message} · sent as written' : "Couldn't translate · sent as written");
        AppState.instance.send(chat, full, lp: lp);
      });
      return;
    }
    AppState.instance.send(chat, full, lp: lp);
  }

  @override
  Widget build(BuildContext context) {
    final tp = chat.themePalette;
    if (tp == null) return _build(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Theme(data: dark ? AppTheme.dark(paletteAt(tp)) : AppTheme.light(paletteAt(tp)), child: Builder(builder: _build));
  }

  Future<void> _chatTheme() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sh) => StatefulBuilder(
        builder: (ctx, set) {
          final bc = ctx.bc;
          void apply(VoidCallback f) {
            f();
            set(() {});
            setState(() {});
            AppState.instance.changed();
          }
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.fromLTRB(22, 0, 22, 4), child: Text('Chat theme', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 10), child: Text('Only for this chat, only on your phone', style: TextStyle(fontSize: 12.5, color: bc.muted))),
              Padding(padding: const EdgeInsets.fromLTRB(22, 4, 22, 8), child: Text('Colour', style: TextStyle(color: bc.muted, fontSize: 13))),
              SizedBox(
                height: 62,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                  for (var i = 0; i < palettes.length; i++)
                    GestureDetector(
                      onTap: () => apply(() => chat.themePalette = i),
                      child: Container(
                        width: 46,
                        height: 46,
                        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ctx.isDark ? palettes[i].dark : palettes[i].light,
                          gradient: palettes[i].linear,
                          border: chat.themePalette == i ? Border.all(color: bc.text, width: 2.5) : null,
                        ),
                        child: chat.themePalette == i ? Icon(Icons.check_rounded, color: palettes[i].onPrimary) : null,
                      ),
                    ),
                ]),
              ),
              Padding(padding: const EdgeInsets.fromLTRB(22, 12, 22, 8), child: Text('Wallpaper', style: TextStyle(color: bc.muted, fontSize: 13))),
              SizedBox(
                height: 120,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                  for (final w in Wallpaper.values)
                    GestureDetector(
                      onTap: () => apply(() => chat.themeWallpaper = w.index),
                      child: Container(
                        width: 70,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: bc.raised,
                          border: Border.all(color: chat.themeWallpaper == w.index ? bc.text : bc.line, width: chat.themeWallpaper == w.index ? 2.5 : 1),
                        ),
                        child: Stack(fit: StackFit.expand, children: [
                          if (w.asset != null) Image.asset(w.asset!, fit: BoxFit.cover),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: double.infinity,
                              color: Colors.black45,
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text(w.label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10.5)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 6),
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('Use app theme'),
                subtitle: const Text('Remove this chat\'s own colour and wallpaper'),
                onTap: () {
                  apply(() {
                    chat.themePalette = null;
                    chat.themeWallpaper = null;
                  });
                  Navigator.pop(sh);
                },
              ),
              const SizedBox(height: 8),
            ]),
          );
        },
      ),
    );
  }

  Widget _build(BuildContext context) {
    final bc = context.bc;
    return PopScope(
      canPop: _sel.isEmpty && _editing == null,
      onPopInvokedWithResult: (did, _) {
        if (did) return;
        if (_sel.isNotEmpty) {
          _clearSel();
        } else if (_editing != null) {
          _ctrl.clear();
          setState(() => _editing = null);
        }
      },
      child: Scaffold(
      appBar: _sel.isNotEmpty ? _selectionBar() : AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: chat.isNotes
              ? (chat.photo == null ? null : () => PhotoViewerScreen.open(context, chat.photo, chat.name))
              : chat.isBroadcast
                  ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BroadcastEditor(existing: chat)))
                  : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => chat.isRealGroup ? GroupInfoScreen(chat: chat) : ChatInfoScreen(chat: chat))),
          child: Row(children: [
            Hero(tag: 'av-${chat.id}', child: Avatar(initials: chat.initials, colorIndex: chat.colorIndex, photo: chat.photo, size: 38)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(chat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: bc.text)),
                ListenableBuilder(
                  listenable: AppState.instance,
                  builder: (context, _) {
                    final text = chat.typing
                        ? (chat.typingName != null ? '${chat.typingName} is typing…' : 'typing…')
                        : chat.isRealGroup
                            ? (chat.left ? "You're no longer a member" : Messenger.instance.memberLine(chat))
                            : chat.isNotes
                                ? 'Message yourself'
                                : chat.isBroadcast
                                ? chat.about
                                : chat.isReal
                                ? (chat.presence ?? '')
                                : (chat.isGroup ? chat.about : (chat.online ? 'online' : 'last seen today'));
                    return AnimatedSize(
                      duration: Mitti.medium,
                      curve: Curves.easeOut,
                      alignment: Alignment.topLeft,
                      child: text.isEmpty
                          ? const SizedBox(width: double.infinity)
                          : AnimatedSwitcher(
                              duration: Mitti.medium,
                              transitionBuilder: (c, a) => FadeTransition(
                                opacity: a,
                                child: SlideTransition(position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(a), child: c),
                              ),
                              child: _HeaderSubtitle(
                                key: ValueKey(text),
                                text: text,
                                style: TextStyle(fontSize: 12, color: chat.typing ? context.primary : bc.muted),
                              ),
                            ),
                    );
                  },
                ),
              ]),
            ),
          ]),
        ),
        actions: [
          if (!chat.isNotes && !chat.isBroadcast) ...[
            IconButton(
              onPressed: chat.peerId != null ? () => CallService.instance.start(chat, video: true) : () => GroupCallService.instance.start(chat, video: true),
              icon: const Icon(Icons.videocam_outlined),
            ),
            IconButton(
              onPressed: chat.peerId != null ? () => CallService.instance.start(chat, video: false) : () => GroupCallService.instance.start(chat, video: false),
              icon: const Icon(Icons.call_outlined),
            ),
          ],
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'search') Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatSearchScreen(chat: chat)));
              if (v == 'media') Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatMediaScreen(chat: chat)));
              if (v == 'theme') _chatTheme();
              if (v == 'translate') translateSettings(context, chat).then((_) => _autoTranslate());
              if (v == 'info') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => chat.isRealGroup ? GroupInfoScreen(chat: chat) : ChatInfoScreen(chat: chat)));
              }
            },
            itemBuilder: (_) => [
              if (!chat.isNotes && !chat.isBroadcast) const PopupMenuItem(value: 'info', child: Text('View info')),
              const PopupMenuItem(value: 'search', child: Text('Search')),
              const PopupMenuItem(value: 'media', child: Text('Media, links and docs')),
              const PopupMenuItem(value: 'theme', child: Text('Chat theme')),
              if (chat.isReal && !chat.isNotes) const PopupMenuItem(value: 'translate', child: Text('Translate')),
            ],
          ),
        ],
      ),
      body: ChatBackground(
        wallpaper: chat.themeWallpaper == null ? null : Wallpaper.values[chat.themeWallpaper!.clamp(0, Wallpaper.values.length - 1)],
        child: Column(children: [
          if (chat.pinnedId != null)
            Builder(builder: (context) {
              Message? pm;
              for (final x in chat.messages) {
                if (x.id == chat.pinnedId) pm = x;
              }
              if (pm == null || pm.deleted) return const SizedBox.shrink();
              final text = pm.text.isNotEmpty ? pm.text : ((pm.media?['name'] ?? pm.media?['q'] ?? pm.media?['title'] ?? 'Media') as String);
              return Material(
                color: bc.surface,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.push_pin_rounded, color: context.primary, size: 20),
                  title: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: bc.text)),
                  trailing: (!chat.isRealGroup || Messenger.instance.canEditGroup(chat))
                      ? IconButton(icon: Icon(Icons.close_rounded, size: 18, color: bc.muted), tooltip: 'Unpin', onPressed: () => Messenger.instance.pin(chat, null))
                      : null,
                ),
              );
            }),
          ListenableBuilder(
            listenable: AppState.instance,
            builder: (context, _) {
              final n = Messenger.instance.scheduledIn(chat).length;
              if (n == 0) return const SizedBox.shrink();
              return Material(
                color: bc.raised,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScheduledScreen(chat: chat))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    child: Row(children: [
                      Icon(Icons.schedule_rounded, size: 18, color: context.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text('$n scheduled message${n == 1 ? '' : 's'}', style: TextStyle(color: context.primary, fontSize: 13.5))),
                      Text('View', style: TextStyle(color: context.primary, fontWeight: FontWeight.w600, fontSize: 13.5)),
                    ]),
                  ),
                ),
              );
            },
          ),
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
                            chat.isReal
                                ? '🔒 Messages and calls are end-to-end encrypted. Only people in this chat can read them.'
                                : 'Demo chat: these sample messages stay on this phone only.',
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
                    if (m.kind == MsgKind.call) {
                      return CallRecordBubble(m: m, onTap: () => CallService.instance.start(chat, video: m.media?['v'] == true));
                    }
                    if (m.kind == MsgKind.system) {
                      return GestureDetector(
                        onTap: m.text.contains('security code') && chat.peerId != null
                            ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SafetyNumberScreen(chat: chat)))
                            : null,
                        child: _SystemPill(text: m.text),
                      );
                    }
                    return _SwipeToReply(
                      key: ValueKey('sw_${m.id}'),
                      onReply: () {
                        setState(() => _replyTo = m);
                        _focus.requestFocus();
                      },
                      child: _Bubble(
                        key: ValueKey(m.id),
                        m: m,
                        chat: chat,
                        selected: _sel.contains(m.id),
                        selecting: _sel.isNotEmpty,
                        onLongPress: (ctx) => _onLongPress(m, ctx),
                        onTap: () => m.media?['sched'] != null ? scheduledOptions(context, chat, m) : _onTapMsg(m),
                        onReply: (x) => setState(() => _replyTo = x),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_recording && _recLocked)
            _RecordingBar(
              elapsed: _recElapsed,
              amps: _amps,
              paused: _recPaused,
              onCancel: () => _stopRecording(send: false),
              onPause: _togglePause,
              onSend: () => _stopRecording(send: true),
            )
          else if (Messenger.instance.isBlocked(chat.peerId))
            InkWell(
              onTap: () => confirmBlock(context, chat),
              child: Container(
                width: double.infinity,
                color: bc.surface,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Text('You blocked this contact. Tap to unblock.', textAlign: TextAlign.center, style: TextStyle(color: bc.muted)),
              ),
            )
          else if (chat.isRealGroup && !chat.left && !Messenger.instance.canSendInGroup(chat))
            Container(
              width: double.infinity,
              color: bc.surface,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Text('Only admins can send messages', textAlign: TextAlign.center, style: TextStyle(color: bc.muted)),
            )
          else if (chat.left)
            Container(
              width: double.infinity,
              color: bc.surface,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Text("You can't send messages to this group because you're no longer a member.",
                  textAlign: TextAlign.center, style: TextStyle(color: bc.muted)),
            )
          else ...[
          if (_lp != null && !_recording)
            Container(
              color: Colors.transparent,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: LinkPreviewCard(lp: _lp!, fg: bc.text, bg: bc.raised, onClose: () => setState(() {
                _lpOff = _lp!['u'] as String?;
                _lp = null;
              })),
            ),
          if (chat.sendTranslate != null && !_recording)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(children: [
                Icon(Icons.translate_rounded, size: 15, color: context.primary),
                const SizedBox(width: 6),
                Expanded(child: Text('Sending in ${Translate.instance.nameOf(chat.sendTranslate!)}', style: TextStyle(color: context.primary, fontSize: 12.5))),
                GestureDetector(
                  onTap: () => setState(() {
                    chat.sendTranslate = null;
                    AppState.instance.changed();
                  }),
                  child: Icon(Icons.close_rounded, size: 16, color: bc.muted),
                ),
              ]),
            ),
          if (!_recording && _editing == null)
            Builder(builder: (context) {
              final qs = quickRepliesFor(_ctrl.text);
              if (qs.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: bc.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, -2))],
                ),
                child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                  for (final q in qs)
                    InkWell(
                      onTap: () {
                        final t = q['t'] ?? '';
                        _ctrl.text = t;
                        _ctrl.selection = TextSelection.collapsed(offset: t.length);
                        setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('/${q['k']}', style: TextStyle(color: context.primary, fontWeight: FontWeight.w700)),
                          Text(q['t'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: bc.muted, fontSize: 13)),
                        ]),
                      ),
                    ),
                ]),
              );
            }),
          _Composer(
            onAttach: _attach,
            mic: _MicState(
              recording: _recording && !_recLocked,
              elapsed: _recElapsed,
              drag: _drag,
              onDown: _micDown,
              onMove: _micMove,
              onUp: () => _micUp(),
              onCancel: () => _micUp(cancelled: true),
            ),
            onCamera: _openCamera,
            focus: _focus,
            emojiOpen: _emoji,
            onEmoji: () {
              if (_emoji) {
                setState(() => _emoji = false);
                _focus.requestFocus();
              } else {
                FocusScope.of(context).unfocus();
                setState(() => _emoji = true);
              }
            },
            onFieldTap: () {
              if (_emoji) setState(() => _emoji = false);
            },
            ctrl: _ctrl,
            replyTo: _replyTo,
            editing: _editing,
            onCancelReply: () {
              if (_editing != null) _ctrl.clear();
              setState(() {
                _replyTo = null;
                _editing = null;
              });
            },
            onSend: _send,
            onScheduleSend: chat.isReal && !chat.isBroadcast && !chat.isNotes
                ? () async {
                    final text = _ctrl.text;
                    if (await scheduleFromComposer(context, chat, text) && mounted) {
                      _ctrl.clear();
                      setState(() => _replyTo = null);
                    }
                  }
                : null,
            onChanged: () {
              setState(() {});
              if (_ctrl.text.isNotEmpty) Messenger.instance.typing(chat);
              _watchLink();
            },
          ),
          ],
          if (_emoji && !_recording && !chat.left)
            SizedBox(
              height: 340,
              child: Column(children: [
                // WhatsApp-style top bar: search · [emoji | GIF | sticker] · backspace
                Container(
                  color: bc.surface,
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                  child: Row(children: [
                    SizedBox(
                      width: 48,
                      child: _panel == 0
                          ? IconButton(
                              onPressed: () => setState(() => _emojiSearch = !_emojiSearch),
                              icon: Icon(_emojiSearch ? Icons.close_rounded : Icons.search_rounded, color: bc.muted),
                            )
                          : null,
                    ),
                    Expanded(
                      child: Center(
                        child: Container(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: bc.line)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            for (final (i, icon) in const [(0, Icons.emoji_emotions_outlined), (2, Icons.gif_box_outlined), (1, Icons.sticky_note_2_outlined)])
                              InkWell(
                                borderRadius: BorderRadius.circular(22),
                                onTap: () => setState(() {
                                  _panel = i;
                                  _emojiSearch = false;
                                }),
                                child: AnimatedContainer(
                                  duration: Mitti.fast,
                                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: _panel == i ? context.primary.withOpacity(0.18) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: Icon(icon, size: 24, color: _panel == i ? context.primary : bc.muted),
                                ),
                              ),
                          ]),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: _panel == 0
                          ? IconButton(
                              onPressed: () {
                                final t = _ctrl.text;
                                if (t.isEmpty) return;
                                _ctrl.text = t.characters.skipLast(1).toString();
                                setState(() {});
                              },
                              icon: Icon(Icons.backspace_outlined, color: bc.muted),
                            )
                          : null,
                    ),
                  ]),
                ),
                Expanded(
                  child: _panel == 0
                      ? (_emojiSearch
                          ? _EmojiSearch(onPick: (e) {
                              _ctrl.text = _ctrl.text + e;
                              setState(() {});
                            })
                          : EmojiPicker(
                              textEditingController: _ctrl,
                              onEmojiSelected: (_, __) => setState(() {}),
                              config: Config(
                                height: 290,
                                viewOrderConfig: const ViewOrderConfig(
                                  top: EmojiPickerItem.searchBar,
                                  middle: EmojiPickerItem.emojiView,
                                  bottom: EmojiPickerItem.categoryBar,
                                ),
                                emojiViewConfig: EmojiViewConfig(backgroundColor: bc.bg, columns: 8, emojiSizeMax: 28),
                                categoryViewConfig: CategoryViewConfig(
                                  backgroundColor: bc.surface,
                                  indicatorColor: context.primary,
                                  iconColor: bc.muted,
                                  iconColorSelected: context.primary,
                                  backspaceColor: context.primary,
                                  dividerColor: bc.line,
                                ),
                                bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
                                searchViewConfig: SearchViewConfig(backgroundColor: bc.surface, buttonIconColor: bc.muted),
                              ),
                            ))
                      : _panel == 1
                          ? _StickerPanel(onSend: _sendSticker, onCreate: _createSticker)
                          : GifPanel(onSend: _sendKlipy, onPickFromPhone: _pickGif),
                ),
              ]),
            ),
        ]),
      ),
    ),
    );
  }
}

class _Bubble extends StatefulWidget {
  final Message m;
  final Chat chat;
  final void Function(BuildContext bubble) onLongPress;
  final VoidCallback onTap;
  final bool selected, selecting;
  final void Function(Message m) onReply;
  const _Bubble({
    super.key,
    required this.m,
    required this.chat,
    required this.onLongPress,
    required this.onTap,
    required this.onReply,
    this.selected = false,
    this.selecting = false,
  });
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
    final caption = m.text.trim().isEmpty
        ? null
        : Padding(padding: const EdgeInsets.fromLTRB(6, 6, 6, 0), child: LinkText(m.text, style: TextStyle(fontSize: 15, color: fg, height: 1.35), linkColor: me ? Colors.white : context.primary));
    final accent = me ? Colors.white : context.primary;
    if (m.deleted) {
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block_rounded, size: 16, color: fg.withOpacity(0.7)),
        const SizedBox(width: 6),
        Text(me ? 'You deleted this message' : 'This message was deleted',
            style: TextStyle(fontSize: 14.5, fontStyle: FontStyle.italic, color: fg.withOpacity(0.75))),
      ]);
    } else if (m.kind == MsgKind.image && m.media?['stk'] == true) {
      content = StickerContent(m: m);
    } else if (m.kind == MsgKind.image && m.media?['once'] == true) {
      content = ViewOnceContent(chat: widget.chat, m: m, fg: fg);
    } else if (m.kind == MsgKind.poll) {
      content = PollContent(chat: widget.chat, m: m, fg: fg, accent: accent);
    } else if (m.kind == MsgKind.checklist) {
      content = ChecklistContent(chat: widget.chat, m: m, fg: fg, accent: accent);
    } else if (m.kind == MsgKind.ledger) {
      content = LedgerContent(chat: widget.chat, m: m, fg: fg, accent: accent);
    } else if (m.kind == MsgKind.location) {
      content = LocationContent(chat: widget.chat, m: m, fg: fg);
    } else if (m.kind == MsgKind.contact) {
      content = ContactContent(m: m, fg: fg);
    } else if (m.kind == MsgKind.event) {
      content = EventContent(m: m, fg: fg);
    } else if (m.kind == MsgKind.video) {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [VideoContent(m: m, fg: fg), if (caption != null) caption]);
    } else if (m.kind == MsgKind.image) {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [ImageContent(m: m, fg: fg, onOpen: () => ChatPhotoScreen.open(context, widget.chat, m, onReply: widget.onReply)), if (caption != null) caption]);
    } else if (m.kind == MsgKind.doc && const {'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac', 'amr'}.contains(MediaFiles.ext((m.media?['name'] as String?) ?? ''))) {
      // Audio files play right in the chat, like WhatsApp.
      content = VoiceContent(m: m, fg: fg, accent: me ? Colors.white24 : context.primary);
    } else if (m.kind == MsgKind.doc) {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [DocContent(m: m, fg: fg), if (caption != null) caption]);
    } else if (m.kind == MsgKind.voice && (m.media != null || m.mediaPath != null)) {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        VoiceContent(m: m, fg: fg, accent: me ? Colors.white24 : context.primary),
        TranscriptLine(m: m, fg: fg, accent: me ? Colors.white : context.primary),
      ]);
    } else if (m.kind == MsgKind.voice) {
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
        if (m.media?['sr'] is Map) _StatusQuote(sr: (m.media!['sr'] as Map).cast<String, dynamic>(), me: me, fg: fg),
        if (m.media?['mention'] is Map) _MentionCard(md: (m.media!['mention'] as Map).cast<String, dynamic>(), fg: fg, me: me),
        if (m.media?['lp'] is Map)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280, minWidth: 280),
            child: LinkPreviewCard(
              large: true,
              lp: (m.media!['lp'] as Map).cast<String, dynamic>(),
              fg: fg,
              bg: (me ? Colors.black : context.primary).withOpacity(me ? 0.14 : 0.08),
            ),
          ),
        LinkText(quoted ? lines.skip(1).join('\n') : m.text,
            style: TextStyle(fontSize: 15, color: fg, height: 1.35), linkColor: me ? Colors.white : context.primary),
        if (m.media?['tr'] is Map) TranslationLine(tr: (m.media!['tr'] as Map).cast<String, dynamic>(), fg: fg),
        if (me && m.media?['orig'] is String) TranslationLine(tr: {'t': m.media!['orig'], 'label': 'You wrote'}, fg: fg),
      ]);
    }

    final bare = !m.deleted &&
        ((m.kind == MsgKind.image && m.media?['stk'] == true) || (m.kind == MsgKind.text && m.media?['sr'] == null && m.media?['mention'] == null && isBigEmoji(m.text)));
    if (bare && m.kind == MsgKind.text) content = Text(m.text.trim(), style: const TextStyle(fontSize: 56, height: 1.15));
    final metaFg = bare ? bc.muted : fg;
    // Photo / video without a caption: time sits on the picture, like WhatsApp.
    final overlayMeta = !m.deleted &&
        (m.kind == MsgKind.image || m.kind == MsgKind.video) &&
        m.media?['once'] != true &&
        m.media?['stk'] != true &&
        m.text.trim().isEmpty;
    Widget metaRow(Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
          if (m.media?['ed'] == true) ...[Text('Edited ', style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: c.withOpacity(0.7)))],
          if (m.starred) ...[Icon(Icons.star_rounded, size: 12, color: c.withOpacity(0.8)), const SizedBox(width: 3)],
          if (m.expiresAt != null) ...[Icon(Icons.timer_outlined, size: 11, color: c.withOpacity(0.8)), const SizedBox(width: 3)],
          if (Messenger.instance.reminders.containsKey(m.id)) ...[Icon(Icons.notifications_active_outlined, size: 12, color: c.withOpacity(0.85)), const SizedBox(width: 3)],
          if (m.media?['sched'] != null) ...[Icon(Icons.schedule_rounded, size: 12, color: c.withOpacity(0.85)), const SizedBox(width: 3)],
          Text(m.media?['sched'] != null ? dayTime(m.time) : hhmm(m.time), style: TextStyle(fontSize: 10.5, color: c.withOpacity(0.85))),
          if (me) ...[const SizedBox(width: 4), Ticks(status: m.status, color: bare ? bc.muted : Colors.white, readColor: kReadBlueOnBubble)],
        ]);
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
      margin: EdgeInsets.only(top: 4, bottom: m.reaction != null ? 14 : 4),
      padding: bare
          ? const EdgeInsets.fromLTRB(4, 2, 4, 2)
          : (!m.deleted && (m.kind == MsgKind.image || m.kind == MsgKind.video) && m.media?['once'] != true)
              ? EdgeInsets.fromLTRB(3, 3, 3, overlayMeta ? 3 : 6)
              : const EdgeInsets.fromLTRB(14, 10, 12, 8),
      decoration: bare ? null : BoxDecoration(
        color: bg,
        gradient: me ? bc.accentGradient : null,
        borderRadius: radius,
        boxShadow: me ? null : const [BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        if (!me && widget.chat.isGroup && m.from != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(Messenger.instance.nameFor(m.from!),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Mitti.avatarColors[m.from!.length % Mitti.avatarColors.length])),
            ),
          ),
        if (m.media?['fw'] == true && !m.deleted)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.shortcut_rounded, size: 14, color: fg.withOpacity(0.6)),
                const SizedBox(width: 3),
                Text('Forwarded', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: fg.withOpacity(0.6))),
              ]),
            ),
          ),
        if (m.media?['auto'] == true && !m.deleted)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.reply_rounded, size: 14, color: fg.withOpacity(0.6)),
                const SizedBox(width: 3),
                Text('Auto-reply', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: fg.withOpacity(0.6))),
              ]),
            ),
          ),
        if (overlayMeta)
          Stack(children: [
            content,
            Positioned(
              right: 8,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
                child: metaRow(Colors.white),
              ),
            ),
          ])
        else ...[
          content,
          const SizedBox(height: 3),
          metaRow(metaFg),
        ],
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
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.selecting ? widget.onTap : null,
          child: Container(
            // Selected: the whole row is highlighted, like WhatsApp.
            color: widget.selected ? context.primary.withOpacity(0.22) : Colors.transparent,
            child: Align(
              alignment: me ? Alignment.centerRight : Alignment.centerLeft,
              child: Builder(
                builder: (bctx) => GestureDetector(
                  onTap: widget.selecting ? widget.onTap : null,
                  onLongPress: () => widget.onLongPress(bctx),
                  // While selecting, taps select instead of opening photos/links.
                  child: IgnorePointer(ignoring: widget.selecting, child: withReaction),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController ctrl;
  final Message? replyTo;
  final Message? editing;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;
  final VoidCallback? onScheduleSend;
  final VoidCallback onChanged;
  final VoidCallback onAttach;
  final _MicState mic;
  final VoidCallback onCamera;
  final VoidCallback onEmoji;
  final VoidCallback onFieldTap;
  final FocusNode focus;
  final bool emojiOpen;
  const _Composer({
    required this.onCamera,
    required this.onEmoji,
    required this.onFieldTap,
    required this.focus,
    required this.emojiOpen,
    required this.ctrl,
    required this.replyTo,
    this.editing,
    required this.onCancelReply,
    required this.onSend,
    this.onScheduleSend,
    required this.onChanged,
    required this.onAttach,
    required this.mic,
  });

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final hasText = ctrl.text.trim().isNotEmpty;
    // No strip behind the typing box: the chat wallpaper shows, like WhatsApp.
    return Container(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (editing != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: bc.raised,
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: context.primary, width: 3)),
              ),
              child: Row(children: [
                Icon(Icons.edit_outlined, size: 18, color: context.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Edit message', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.primary)),
                    Text(editing!.text.split('\n').last, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: bc.muted)),
                  ]),
                ),
                IconButton(onPressed: onCancelReply, icon: Icon(Icons.close_rounded, size: 18, color: bc.muted)),
              ]),
            ),
          if (replyTo != null && editing == null)
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
                child: mic.recording
                    ? _HoldingStrip(elapsed: mic.elapsed, dragX: mic.drag.dx)
                    : Container(
                  decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(24)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    IconButton(onPressed: onEmoji, icon: Icon(emojiOpen ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined, color: bc.muted)),
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        focusNode: focus,
                        onTap: onFieldTap,
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
                    IconButton(onPressed: onAttach, icon: Icon(Icons.attach_file_rounded, color: bc.muted)),
                    if (!hasText) IconButton(onPressed: onCamera, icon: Icon(Icons.photo_camera_outlined, color: bc.muted)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              if (hasText)
                GestureDetector(
                  onTap: onSend,
                  onLongPress: editing == null ? onScheduleSend : null,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(color: context.primary, gradient: bc.accentGradient, shape: BoxShape.circle),
                    child: Icon(Icons.send_rounded, color: Theme.of(context).colorScheme.onPrimary),
                  ),
                )
              else
                _MicButton(mic: mic),
            ]),
          ),
        ]),
      ),
    );
  }
}


/// Type a word ("love", "laugh") to find emoji.
class _EmojiSearch extends StatefulWidget {
  final void Function(String emoji) onPick;
  const _EmojiSearch({required this.onPick});
  @override
  State<_EmojiSearch> createState() => _EmojiSearchState();
}

class _EmojiSearchState extends State<_EmojiSearch> {
  final _utils = EmojiPickerUtils();
  List<Emoji> _found = [];

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _found = []);
      return;
    }
    final r = await _utils.searchEmoji(q.trim(), defaultEmojiSet);
    if (mounted) setState(() => _found = r);
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return ColoredBox(
      color: bc.bg,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: TextField(
            autofocus: true,
            onChanged: _search,
            style: TextStyle(color: bc.text),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: bc.raised,
              prefixIcon: Icon(Icons.search_rounded, color: bc.muted, size: 20),
              hintText: 'Search emoji',
              hintStyle: TextStyle(color: bc.muted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 8,
            padding: const EdgeInsets.all(6),
            children: [
              for (final e in _found)
                InkWell(onTap: () => widget.onPick(e.emoji), child: Center(child: Text(e.emoji, style: const TextStyle(fontSize: 26)))),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Built-in BAATLY pack + "My stickers" (make one from a photo).
class _StickerPanel extends StatefulWidget {
  final void Function(String path) onSend;
  final VoidCallback onCreate;
  const _StickerPanel({required this.onSend, required this.onCreate});
  @override
  State<_StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<_StickerPanel> {
  @override
  void initState() {
    super.initState();
    StickerStore.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return ColoredBox(
      color: bc.bg,
      child: ListenableBuilder(
        listenable: StickerStore.instance,
        builder: (context, _) {
          final st = StickerStore.instance;
          Widget tile(String p, {bool mine = false}) => InkWell(
                onTap: () => widget.onSend(p),
                onLongPress: mine
                    ? () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: const Text('Remove this sticker?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('No')),
                              TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
                            ],
                          ),
                        );
                        if (ok == true) st.remove(p);
                      }
                    : null,
                child: Padding(padding: const EdgeInsets.all(6), child: Image.file(File(p), fit: BoxFit.contain, cacheWidth: 220)),
              );
          Text head(String t) => Text(t, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: bc.muted));
          return CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              sliver: SliverToBoxAdapter(child: head('MY STICKERS')),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              sliver: SliverGrid.count(crossAxisCount: 4, children: [
                InkWell(
                  onTap: widget.onCreate,
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: bc.line, width: 1.5)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_photo_alternate_outlined, color: context.primary),
                      const SizedBox(height: 4),
                      Text('Create', style: TextStyle(fontSize: 11.5, color: bc.muted)),
                    ]),
                  ),
                ),
                for (final p in st.mine) tile(p, mine: true),
              ]),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              sliver: SliverToBoxAdapter(child: head('BAATLY')),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              sliver: SliverGrid.count(crossAxisCount: 4, children: [for (final p in st.builtIn) tile(p)]),
            ),
          ]);
        },
      ),
    );
  }
}

/// Everything the composer needs to draw the hold-to-record mic.
class _MicState {
  final bool recording;
  final Duration elapsed;
  final Offset drag;
  final VoidCallback onDown, onUp, onCancel;
  final void Function(Offset delta) onMove;
  const _MicState({
    required this.recording,
    required this.elapsed,
    required this.drag,
    required this.onDown,
    required this.onMove,
    required this.onUp,
    required this.onCancel,
  });
}

String _fmtRec(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Hold to record, slide left to cancel, slide up to lock.
class _MicButton extends StatelessWidget {
  final _MicState mic;
  const _MicButton({required this.mic});
  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final rec = mic.recording;
    final dx = rec ? mic.drag.dx.clamp(-110.0, 0.0) : 0.0;
    final dy = rec ? mic.drag.dy.clamp(-90.0, 0.0) : 0.0;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => mic.onDown(),
      onPointerMove: (e) => mic.onMove(e.delta),
      onPointerUp: (_) => mic.onUp(),
      onPointerCancel: (_) => mic.onCancel(),
      child: SizedBox(
        width: 50,
        height: 50,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          if (rec)
            Positioned(
              bottom: 74 + (-dy * 0.5),
              child: Opacity(
                opacity: (1 + dy / 90).clamp(0.3, 1.0),
                child: Container(
                  width: 40,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: bc.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock_open_rounded, size: 20, color: bc.muted),
                    const SizedBox(height: 4),
                    Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: bc.muted),
                  ]),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(dx, dy),
            child: AnimatedScale(
              scale: rec ? 1.5 : 1,
              duration: Mitti.fast,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: context.primary, gradient: context.bc.accentGradient, shape: BoxShape.circle),
                child: Icon(Icons.mic_rounded, color: Theme.of(context).colorScheme.onPrimary),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Replaces the text box while the finger is holding the mic.
class _HoldingStrip extends StatelessWidget {
  final Duration elapsed;
  final double dragX;
  const _HoldingStrip({required this.elapsed, required this.dragX});
  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final blink = (elapsed.inMilliseconds ~/ 500).isEven;
    final pull = dragX.clamp(-110.0, 0.0);
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(24)),
      child: Row(children: [
        AnimatedOpacity(
          opacity: blink ? 1 : 0.25,
          duration: const Duration(milliseconds: 250),
          child: const Icon(Icons.mic_rounded, color: Color(0xFFE53935), size: 22),
        ),
        const SizedBox(width: 8),
        Text(_fmtRec(elapsed), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: bc.text)),
        Expanded(
          child: Transform.translate(
            offset: Offset(pull * 0.6, 0),
            child: Opacity(
              opacity: (1 + pull / 110).clamp(0.2, 1.0),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Icon(Icons.chevron_left_rounded, color: bc.muted, size: 20),
                Text('Slide to cancel', style: TextStyle(color: bc.muted, fontSize: 14)),
                const SizedBox(width: 6),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Hands-free recording (after sliding up to lock): timer, live waveform,
/// delete, pause/resume and send.
class _RecordingBar extends StatelessWidget {
  final Duration elapsed;
  final List<double> amps;
  final bool paused;
  final VoidCallback onCancel, onPause, onSend;
  const _RecordingBar({
    required this.elapsed,
    required this.amps,
    required this.paused,
    required this.onCancel,
    required this.onPause,
    required this.onSend,
  });
  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Container(
      color: bc.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Text(_fmtRec(elapsed), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: bc.text)),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: CustomPaint(painter: _WavePainter(amps, paused ? bc.muted : context.primary)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              IconButton(
                onPressed: onCancel,
                tooltip: 'Delete',
                icon: Icon(Icons.delete_outline_rounded, color: bc.muted, size: 26),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onPause,
                icon: Icon(paused ? Icons.mic_rounded : Icons.pause_rounded, color: const Color(0xFFE53935)),
                label: Text(paused ? 'Resume' : 'Pause', style: const TextStyle(color: Color(0xFFE53935), fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onSend,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: context.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Live bars from the mic level, newest on the right.
class _WavePainter extends CustomPainter {
  final List<double> amps;
  final Color color;
  _WavePainter(this.amps, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    const step = 4.0;
    final n = (size.width / step).floor();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final start = amps.length > n ? amps.length - n : 0;
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      final j = start + i;
      final v = j < amps.length ? amps[j] : 0.06;
      final x = i * step + 1.5;
      final h = (v * size.height / 2).clamp(1.5, size.height / 2);
      canvas.drawLine(Offset(x, mid - h), Offset(x, mid + h), paint..color = j < amps.length ? color : color.withOpacity(0.25));
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}


/// Centered note in group chats ("Riya added Aman").
/// "Voice call · 4 min" / "Missed video call · Tap to call back" inside a chat.
class CallRecordBubble extends StatelessWidget {
  final Message m;
  final VoidCallback onTap;
  const CallRecordBubble({super.key, required this.m, required this.onTap});

  static String durText(int s) => s >= 60 ? '${s ~/ 60} min' : '$s sec';

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final me = m.fromMe;
    final video = m.media?['v'] == true;
    final missed = m.media?['missed'] == true;
    final dur = (m.media?['dur'] as int?) ?? 0;
    final title = !me && missed ? (video ? 'Missed video call' : 'Missed voice call') : (video ? 'Video call' : 'Voice call');
    final sub = !me && missed ? 'Tap to call back' : (missed || dur == 0 ? 'No answer' : durText(dur));
    final bg = me ? bc.outBubble : bc.inBubble;
    final fg = me ? bc.onOutBubble : bc.text;
    final iconColor = !me && missed ? const Color(0xFFE5484D) : fg;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(color: bg, gradient: me ? bc.accentGradient : null, borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: fg.withOpacity(0.12), shape: BoxShape.circle),
                  child: Stack(alignment: Alignment.center, children: [
                    Icon(video ? Icons.videocam_rounded : Icons.call_rounded, size: 20, color: iconColor),
                    if (!me && missed) const Positioned(left: 4, bottom: 4, child: Icon(Icons.call_received_rounded, size: 12, color: Color(0xFFE5484D))),
                    if (me) Positioned(left: 4, bottom: 4, child: Icon(Icons.call_made_rounded, size: 12, color: fg.withOpacity(0.8))),
                  ]),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 120),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: fg)),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(fontSize: 13, color: fg.withOpacity(0.75))),
                  ]),
                ),
                const SizedBox(width: 10),
                Text(hhmm(m.time), style: TextStyle(fontSize: 11, color: fg.withOpacity(0.7))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chat header line. "last seen yesterday at 11:30 pm" slides left after a moment
/// and settles on just "11:30 pm", like WhatsApp.
class _HeaderSubtitle extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _HeaderSubtitle({super.key, required this.text, required this.style});

  @override
  State<_HeaderSubtitle> createState() => _HeaderSubtitleState();
}

class _HeaderSubtitleState extends State<_HeaderSubtitle> {
  final _scroll = ScrollController();
  bool _short = false;

  static String? shortOf(String t) {
    if (!t.startsWith('last seen ')) return null;
    final rest = t.substring('last seen '.length);
    final at = rest.lastIndexOf(' at ');
    if (at < 0) return rest.isEmpty ? null : rest;
    // Today / yesterday: just the time. Older: just the date.
    return rest.startsWith('today') || rest.startsWith('yesterday') ? rest.substring(at + 4) : rest.substring(0, at);
  }

  @override
  void initState() {
    super.initState();
    final short = shortOf(widget.text);
    if (short == null) return;
    Future.delayed(const Duration(milliseconds: 1600), () async {
      if (!mounted) return;
      if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
        final ms = (_scroll.position.maxScrollExtent * 18).clamp(500, 2600).toInt();
        await _scroll.animateTo(_scroll.position.maxScrollExtent, duration: Duration(milliseconds: ms), curve: Curves.linear);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
      if (mounted) setState(() => _short = true);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final short = shortOf(widget.text);
    return AnimatedSwitcher(
      duration: Mitti.fast,
      child: _short && short != null
          ? Align(key: const ValueKey('s'), alignment: Alignment.centerLeft, child: Text(short, maxLines: 1, style: widget.style))
          : SingleChildScrollView(
              key: const ValueKey('l'),
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Text(widget.text, maxLines: 1, style: widget.style),
            ),
    );
  }
}

/// Simple copy of a message for the Message info screen.
class _InfoBubble extends StatelessWidget {
  final Message m;
  const _InfoBubble({required this.m});

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final label = switch (m.kind) {
      MsgKind.image => m.text.trim().isEmpty ? '📷 Photo' : '📷 ${m.text}',
      MsgKind.video => m.text.trim().isEmpty ? '🎥 Video' : '🎥 ${m.text}',
      MsgKind.voice => '🎤 Voice message',
      MsgKind.doc => '📄 ${(m.media?['name'] as String?) ?? 'Document'}',
      MsgKind.location => '📍 Location',
      MsgKind.contact => '👤 ${(m.media?['name'] as String?) ?? 'Contact'}',
      MsgKind.poll => '📊 ${(m.media?['q'] as String?) ?? 'Poll'}',
      MsgKind.checklist => '☑️ ${(m.media?['title'] as String?) ?? 'Checklist'}',
      MsgKind.ledger => '₹ ${(m.media?['title'] as String?) ?? 'Hisaab'}',
      MsgKind.event => '📅 ${(m.media?['title'] as String?) ?? 'Event'}',
      _ => m.text,
    };
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
        decoration: BoxDecoration(
          color: bc.outBubble,
          gradient: bc.accentGradient,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 15, color: bc.onOutBubble, height: 1.35)),
          const SizedBox(height: 2),
          Text(hhmm(m.time), style: TextStyle(fontSize: 10.5, color: bc.onOutBubble.withOpacity(0.8))),
        ]),
      ),
    );
  }
}

/// Reply to a status: small copy of that status on top of the message.
class _StatusQuote extends StatelessWidget {
  final Map<String, dynamic> sr;
  final bool me;
  final Color fg;
  const _StatusQuote({required this.sr, required this.me, required this.fg});

  @override
  Widget build(BuildContext context) {
    final accent = me ? Colors.white : context.primary;
    Widget? pic;
    if (sr['th'] is String) {
      try {
        pic = Image.memory(base64Decode(sr['th'] as String), fit: BoxFit.cover, width: 46, height: 52, gaplessPlayback: true);
      } catch (_) {}
    } else if (sr['bg'] is int) {
      pic = Container(width: 46, height: 52, color: Color(sr['bg'] as int), alignment: Alignment.center, child: const Icon(Icons.text_fields_rounded, color: Colors.white70, size: 18));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(minWidth: 200),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: (me ? Colors.black : context.primary).withOpacity(me ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${me ? (sr['n'] ?? 'Status') : 'You'} · Status', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: accent)),
              Text((sr['t'] as String?) ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: fg.withOpacity(0.85))),
            ]),
          ),
        ),
        if (pic != null) pic,
      ]),
    );
  }
}

/// "X mentioned you in their status" card.
class _MentionCard extends StatelessWidget {
  final Map<String, dynamic> md;
  final Color fg;
  final bool me;
  const _MentionCard({required this.md, required this.fg, required this.me});

  @override
  Widget build(BuildContext context) {
    Widget? pic;
    if (md['th'] is String) {
      try {
        pic = Image.memory(base64Decode(md['th'] as String), fit: BoxFit.cover, width: 220, height: 150, gaplessPlayback: true);
      } catch (_) {}
    } else if (md['bg'] is int) {
      pic = Container(
        width: 220,
        height: 150,
        color: Color(md['bg'] as int),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(12),
        child: Text((md['t'] as String?) ?? '', textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (pic != null) ClipRRect(borderRadius: BorderRadius.circular(10), child: pic),
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.alternate_email_rounded, size: 15, color: fg.withOpacity(0.8)),
          const SizedBox(width: 4),
          Flexible(child: Text(me ? 'You mentioned them in your status' : 'Mentioned you in their status', style: TextStyle(fontSize: 13, color: fg.withOpacity(0.85), fontStyle: FontStyle.italic))),
        ]),
      ]),
    );
  }
}

class _SystemPill extends StatelessWidget {
  final String text;
  const _SystemPill({required this.text});
  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: bc.surface.withOpacity(0.92), borderRadius: BorderRadius.circular(10)),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: bc.muted)),
      ),
    );
  }
}

/// Swipe a message to the right to reply to it.
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  const _SwipeToReply({super.key, required this.child, required this.onReply});
  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> with SingleTickerProviderStateMixin {
  double _dx = 0;
  bool _fired = false;
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
    ..addListener(() => setState(() => _dx = _from * (1 - _back.value)));
  double _from = 0;
  static const _trigger = 64.0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        _back.stop();
        setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, 96.0));
        if (!_fired && _dx >= _trigger) {
          _fired = true;
        }
      },
      onHorizontalDragEnd: (_) {
        if (_fired) widget.onReply();
        _fired = false;
        _from = _dx;
        _back.forward(from: 0);
      },
      child: Stack(alignment: Alignment.centerLeft, children: [
        if (_dx > 8)
          Opacity(
            opacity: (_dx / _trigger).clamp(0.0, 1.0),
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: CircleAvatar(radius: 15, backgroundColor: Colors.black26, child: const Icon(Icons.reply_rounded, size: 18, color: Colors.white)),
            ),
          ),
        Transform.translate(offset: Offset(_dx, 0), child: widget.child),
      ]),
    );
  }
}
