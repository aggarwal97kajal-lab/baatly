import 'package:flutter/material.dart';
import 'dart:async';
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
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'chat_info_screen.dart';
import 'media_widgets.dart';
import 'cards.dart';
import 'group_screens.dart';
import 'chat_tools.dart';
import 'location.dart';
import 'safety_screens.dart';
import '../../data/calls.dart';
import '../../data/media.dart';

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
  final _rec = AudioRecorder();
  bool _recording = false;
  DateTime? _recStart;
  Timer? _recTimer;
  String? _recPath;
  bool _emoji = false;
  final _focus = FocusNode();

  Chat get chat => widget.chat;

  void _toast(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
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
      f = await ImagePicker().pickImage(source: src, maxWidth: 2048, imageQuality: 85);
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

  Future<void> _pickVideo() async {
    XFile? f;
    try {
      f = await ImagePicker().pickVideo(source: ImageSource.gallery);
    } catch (_) {
      _toast('Photos permission needed');
      return;
    }
    if (f == null) return;
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
      Messenger.instance.sendMedia(chat, path: kept, kind: MsgKind.video, name: name, seconds: secs, extra: {if (thumb != null) 'thumb': thumb});
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
              item(Icons.photo_camera_rounded, 'Camera', const Color(0xFFC8553D), () => _pickImage(ImageSource.camera)),
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startRecording() async {
    try {
      if (!await _rec.hasPermission()) {
        _toast('Allow microphone to record voice notes');
        return;
      }
      final dir = await MediaFiles.dir();
      _recPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100), path: _recPath!);
      HapticFeedback.mediumImpact();
      setState(() {
        _recording = true;
        _recStart = DateTime.now();
      });
      _recTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => mounted ? setState(() {}) : null);
    } catch (e) {
      _toast("Couldn't start recording ($e)");
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    _recTimer?.cancel();
    final secs = _recStart == null ? 0 : DateTime.now().difference(_recStart!).inSeconds;
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    setState(() => _recording = false);
    path ??= _recPath;
    if (path == null) return;
    if (!send || secs < 1) {
      try {
        await File(path).delete();
      } catch (_) {}
      if (send) _toast('Hold on a bit longer to record');
      return;
    }
    _sendMedia(path, MsgKind.voice, name: 'voice.m4a', seconds: secs);
  }

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
    _recTimer?.cancel();
    _rec.dispose();
    _focus.dispose();
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
    if (m.kind == MsgKind.system) return;
    HapticFeedback.selectionClick();
    final bc = context.bc;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Tall enough for every option (Delete for everyone was cut off before).
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
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
          if (!m.deleted && (!chat.isRealGroup || Messenger.instance.canEditGroup(chat)))
            ListTile(
              leading: Icon(chat.pinnedId == m.id ? Icons.push_pin_outlined : Icons.push_pin_rounded),
              title: Text(chat.pinnedId == m.id ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.pop(sheet);
                Messenger.instance.pin(chat, chat.pinnedId == m.id ? null : m);
              },
            ),
          if (!m.deleted)
            ListTile(
              leading: const Icon(Icons.shortcut_rounded),
              title: const Text('Forward'),
              onTap: () {
                Navigator.pop(sheet);
                forwardMessage(context, m);
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
          if (m.fromMe && !m.deleted && DateTime.now().difference(m.time).inMinutes < 5)
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
              title: Text('Delete for everyone', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () async {
                Navigator.pop(sheet);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Delete message for everyone?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('No')),
                      TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Yes, delete', style: TextStyle(color: Color(0xFFB3261E)))),
                    ],
                  ),
                );
                if (ok == true) Messenger.instance.deleteForEveryone(chat, m);
              },
            ),
        ]),
        ),
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
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => chat.isRealGroup ? GroupInfoScreen(chat: chat) : ChatInfoScreen(chat: chat))),
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
                          ? (chat.typingName != null ? '${chat.typingName} is typing…' : 'typing…')
                          : chat.isRealGroup
                              ? (chat.left ? "You're no longer a member" : Messenger.instance.memberLine(chat))
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
          IconButton(
            onPressed: chat.peerId != null ? () => CallService.instance.start(chat, video: true) : () => showComingSoon(context, 'Group video call'),
            icon: const Icon(Icons.videocam_outlined),
          ),
          IconButton(
            onPressed: chat.peerId != null ? () => CallService.instance.start(chat, video: false) : () => showComingSoon(context, 'Group call'),
            icon: const Icon(Icons.call_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'search') Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatSearchScreen(chat: chat)));
              if (v == 'media') Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatMediaScreen(chat: chat)));
              if (v == 'info') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => chat.isRealGroup ? GroupInfoScreen(chat: chat) : ChatInfoScreen(chat: chat)));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'info', child: Text('View info')),
              PopupMenuItem(value: 'search', child: Text('Search')),
              PopupMenuItem(value: 'media', child: Text('Media, links and docs')),
            ],
          ),
        ],
      ),
      body: ChatBackground(
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
                      child: _Bubble(key: ValueKey(m.id), m: m, chat: chat, onLongPress: () => _msgMenu(m)),
                    );
                  },
                );
              },
            ),
          ),
          if (_recording)
            _RecordingBar(
              seconds: _recStart == null ? 0 : DateTime.now().difference(_recStart!).inSeconds,
              onCancel: () => _stopRecording(send: false),
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
          else
          _Composer(
            onAttach: _attach,
            onMic: _startRecording,
            onCamera: () => _pickImage(ImageSource.camera),
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
            onCancelReply: () => setState(() => _replyTo = null),
            onSend: _send,
            onChanged: () {
              setState(() {});
              if (_ctrl.text.isNotEmpty) Messenger.instance.typing(chat);
            },
          ),
          if (_emoji && !_recording && !chat.left)
            EmojiPicker(
              textEditingController: _ctrl,
              onEmojiSelected: (_, __) => setState(() {}),
              config: Config(
                height: 280,
                emojiViewConfig: EmojiViewConfig(backgroundColor: bc.bg, columns: 8, emojiSizeMax: 28),
                categoryViewConfig: CategoryViewConfig(
                  backgroundColor: bc.surface,
                  indicatorColor: context.primary,
                  iconColor: bc.muted,
                  iconColorSelected: context.primary,
                  backspaceColor: context.primary,
                  dividerColor: bc.line,
                ),
                bottomActionBarConfig: BottomActionBarConfig(backgroundColor: bc.surface, buttonColor: bc.surface, buttonIconColor: bc.muted),
                searchViewConfig: SearchViewConfig(backgroundColor: bc.surface, buttonIconColor: bc.muted),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Bubble extends StatefulWidget {
  final Message m;
  final Chat chat;
  final VoidCallback onLongPress;
  const _Bubble({super.key, required this.m, required this.chat, required this.onLongPress});
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
        : Padding(padding: const EdgeInsets.only(top: 6), child: Text(m.text, style: TextStyle(fontSize: 15, color: fg, height: 1.35)));
    final accent = me ? Colors.white : context.primary;
    if (m.deleted) {
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block_rounded, size: 16, color: fg.withOpacity(0.7)),
        const SizedBox(width: 6),
        Text(me ? 'You deleted this message' : 'This message was deleted',
            style: TextStyle(fontSize: 14.5, fontStyle: FontStyle.italic, color: fg.withOpacity(0.75))),
      ]);
    } else if (m.kind == MsgKind.image && m.media?['once'] == true) {
      content = ViewOnceContent(chat: widget.chat, m: m, fg: fg);
    } else if (m.kind == MsgKind.poll) {
      content = PollContent(chat: widget.chat, m: m, fg: fg, accent: accent);
    } else if (m.kind == MsgKind.location) {
      content = LocationContent(chat: widget.chat, m: m, fg: fg);
    } else if (m.kind == MsgKind.contact) {
      content = ContactContent(m: m, fg: fg);
    } else if (m.kind == MsgKind.event) {
      content = EventContent(m: m, fg: fg);
    } else if (m.kind == MsgKind.video) {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [VideoContent(m: m, fg: fg), if (caption != null) caption]);
    } else if (m.kind == MsgKind.image) {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [ImageContent(m: m, fg: fg), if (caption != null) caption]);
    } else if (m.kind == MsgKind.doc && const {'mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac', 'amr'}.contains(MediaFiles.ext((m.media?['name'] as String?) ?? ''))) {
      // Audio files play right in the chat, like WhatsApp.
      content = VoiceContent(m: m, fg: fg, accent: me ? Colors.white24 : context.primary);
    } else if (m.kind == MsgKind.doc) {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [DocContent(m: m, fg: fg), if (caption != null) caption]);
    } else if (m.kind == MsgKind.voice && (m.media != null || m.mediaPath != null)) {
      content = VoiceContent(m: m, fg: fg, accent: me ? Colors.white24 : context.primary);
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
  final VoidCallback onAttach;
  final VoidCallback onMic;
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
    required this.onCancelReply,
    required this.onSend,
    required this.onChanged,
    required this.onAttach,
    required this.onMic,
  });

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
              GestureDetector(
                onTap: hasText ? onSend : onMic,
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


/// Shown instead of the text box while a voice note is recording.
class _RecordingBar extends StatelessWidget {
  final int seconds;
  final VoidCallback onCancel;
  final VoidCallback onSend;
  const _RecordingBar({required this.seconds, required this.onCancel, required this.onSend});
  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Container(
      color: bc.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(children: [
            IconButton(onPressed: onCancel, tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB3261E))),
            const SizedBox(width: 4),
            const Icon(Icons.fiber_manual_record_rounded, color: Color(0xFFE53935), size: 16),
            const SizedBox(width: 8),
            Text(MediaFiles.fmtDur(seconds), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: bc.text)),
            const SizedBox(width: 10),
            Expanded(child: Text('Recording…', style: TextStyle(color: bc.muted))),
            GestureDetector(
              onTap: onSend,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: context.primary, shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}


/// Centered note in group chats ("Riya added Aman").
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
          HapticFeedback.lightImpact();
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
