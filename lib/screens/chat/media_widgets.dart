import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';

import '../../data/media.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../widgets/photo_viewer.dart';

/// Photo inside a chat bubble: blurred preview until downloaded, tap for full screen.
class ImageContent extends StatelessWidget {
  final Message m;
  final Color fg;
  const ImageContent({super.key, required this.m, required this.fg});

  @override
  Widget build(BuildContext context) {
    final md = m.media ?? {};
    final w = (md['w'] as int?) ?? 4, h = (md['h'] as int?) ?? 3;
    final maxW = MediaQuery.of(context).size.width * 0.66;
    final ratio = (w / h).clamp(0.55, 1.8);
    final path = m.mediaPath;
    final has = path != null && File(path).existsSync();
    Widget img;
    if (has) {
      img = Image.file(File(path), fit: BoxFit.cover, cacheWidth: 900);
    } else if (md['thumb'] is String) {
      img = Image.memory(base64Decode(md['thumb'] as String), fit: BoxFit.cover, filterQuality: FilterQuality.low, gaplessPlayback: true);
    } else {
      img = Container(color: Colors.black26);
    }
    return GestureDetector(
      onTap: () async {
        if (has) {
          PhotoViewerScreen.open(context, path, 'Photo');
        } else {
          final p = await Messenger.instance.downloadMedia(m);
          if (p == null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't download this photo")));
          }
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: maxW,
          height: maxW / ratio,
          child: Stack(fit: StackFit.expand, children: [
            img,
            if (!has || m.busy)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: m.busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Icon(Icons.download_rounded, color: Colors.white),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Document: icon, name, size; tap to download / open.
class DocContent extends StatelessWidget {
  final Message m;
  final Color fg;
  const DocContent({super.key, required this.m, required this.fg});

  @override
  Widget build(BuildContext context) {
    final md = m.media ?? {};
    final name = (md['name'] as String?) ?? 'Document';
    final size = (md['size'] as int?) ?? (m.mediaPath != null && File(m.mediaPath!).existsSync() ? File(m.mediaPath!).lengthSync() : 0);
    final ext = MediaFiles.ext(name).toUpperCase();
    final has = m.mediaPath != null && File(m.mediaPath!).existsSync();
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final p = has ? m.mediaPath : await Messenger.instance.downloadMedia(m);
        if (p == null) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't download this file")));
          return;
        }
        final r = await OpenFilex.open(p);
        if (r.type != ResultType.done && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No app found to open $ext files')));
        }
      },
      child: Container(
        width: MediaQuery.of(context).size.width * 0.62,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: fg.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Container(
            width: 40,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fg.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(ext.isEmpty ? 'FILE' : (ext.length > 4 ? ext.substring(0, 4) : ext),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 2),
              Text('${size > 0 ? MediaFiles.size(size) : ''}${ext.isEmpty ? '' : ' · $ext'}', style: TextStyle(fontSize: 11.5, color: fg.withOpacity(0.75))),
            ]),
          ),
          const SizedBox(width: 6),
          if (m.busy)
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
          else if (!has)
            Icon(Icons.download_rounded, color: fg),
        ]),
      ),
    );
  }
}

/// Voice note with play/pause and a progress bar.
class VoiceContent extends StatefulWidget {
  final Message m;
  final Color fg;
  final Color accent;
  const VoiceContent({super.key, required this.m, required this.fg, required this.accent});
  @override
  State<VoiceContent> createState() => _VoiceContentState();
}

class _VoiceContentState extends State<VoiceContent> {
  static _VoiceContentState? _playing;
  AudioPlayer? _p;
  Duration _pos = Duration.zero;
  Duration? _dur;
  bool _on = false;
  final _subs = <StreamSubscription<dynamic>>[];

  Future<void> _toggle() async {
    if (_on) {
      await _p?.pause();
      return;
    }
    var path = widget.m.mediaPath;
    if (path == null || !File(path).existsSync()) {
      path = await Messenger.instance.downloadMedia(widget.m);
      if (path == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't download this voice note")));
        return;
      }
    }
    if (_playing != null && _playing != this) await _playing!._p?.pause();
    _playing = this;
    if (_p == null) {
      final p = _p = AudioPlayer();
      _subs.add(p.positionStream.listen((d) => mounted ? setState(() => _pos = d) : null));
      _subs.add(p.playerStateStream.listen((st) {
        if (!mounted) return;
        setState(() => _on = st.playing && st.processingState != ProcessingState.completed);
        if (st.processingState == ProcessingState.completed) {
          p.pause();
          p.seek(Duration.zero);
        }
      }));
      _dur = await p.setFilePath(path);
    }
    await _p!.play();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _p?.dispose();
    if (_playing == this) _playing = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    final total = _dur?.inMilliseconds ?? widget.m.voiceSeconds * 1000;
    final v = total > 0 ? (_pos.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
    final shown = _on || _pos > Duration.zero ? _pos.inSeconds : (total ~/ 1000);
    return SizedBox(
      width: 230,
      child: Row(children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: widget.accent, shape: BoxShape.circle),
            child: widget.m.busy
                ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_on ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: v, minHeight: 4, color: fg, backgroundColor: fg.withOpacity(0.25)),
            ),
            const SizedBox(height: 6),
            Text(MediaFiles.fmtDur(shown), style: TextStyle(fontSize: 11, color: fg.withOpacity(0.8))),
          ]),
        ),
      ]),
    );
  }
}

/// Preview a photo before sending, with a caption.
class SendPhotoScreen extends StatefulWidget {
  final String path;
  final String to;
  const SendPhotoScreen({super.key, required this.path, required this.to});
  @override
  State<SendPhotoScreen> createState() => _SendPhotoScreenState();
}

class _SendPhotoScreenState extends State<SendPhotoScreen> {
  final _c = TextEditingController();
  bool _once = false;
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(widget.to)),
      body: SafeArea(
        child: Column(children: [
          Expanded(child: Center(child: Image.file(File(widget.path), fit: BoxFit.contain))),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  style: const TextStyle(color: Colors.white),
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Add a caption…',
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF222222),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'View once',
                onPressed: () {
                  setState(() => _once = !_once);
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    duration: const Duration(seconds: 2),
                    content: Text(_once ? 'Photo set to view once' : 'View once turned off'),
                  ));
                },
                icon: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _once ? Theme.of(context).colorScheme.primary : Colors.transparent,
                    border: Border.all(color: Colors.white, width: 1.6),
                  ),
                  child: const Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 4),
              FloatingActionButton(
                heroTag: 'send-photo',
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                onPressed: () => Navigator.pop(context, (_c.text.trim(), _once)),
                child: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}


/// Video in a chat bubble: tap to download (if needed) and play.
class VideoContent extends StatelessWidget {
  final Message m;
  final Color fg;
  const VideoContent({super.key, required this.m, required this.fg});
  @override
  Widget build(BuildContext context) {
    final md = m.media ?? {};
    final size = (md['size'] as int?) ?? (m.mediaPath != null && File(m.mediaPath!).existsSync() ? File(m.mediaPath!).lengthSync() : 0);
    final dur = (md['dur'] as int?) ?? 0;
    final has = m.mediaPath != null && File(m.mediaPath!).existsSync();
    final w = MediaQuery.of(context).size.width * 0.64;
    return GestureDetector(
      onTap: () async {
        final p = has ? m.mediaPath : await Messenger.instance.downloadMedia(m);
        if (p == null) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't download this video")));
          return;
        }
        if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(path: p)));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: w,
          height: w * 9 / 16,
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF2B2B2B), Color(0xFF111111)])),
          child: Stack(children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: m.busy
                    ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Icon(has ? Icons.play_arrow_rounded : Icons.download_rounded, color: Colors.white, size: 30),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 8,
              child: Row(children: [
                const Icon(Icons.videocam_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 4),
                Text('${dur > 0 ? MediaFiles.fmtDur(dur) : ''}${dur > 0 && size > 0 ? ' · ' : ''}${size > 0 ? MediaFiles.size(size) : ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final String path;
  const VideoPlayerScreen({super.key, required this.path});
  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _c = VideoPlayerController.file(File(widget.path));
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
    });
    _c.addListener(() => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Video')),
      body: !_ready
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : GestureDetector(
              onTap: () => _c.value.isPlaying ? _c.pause() : _c.play(),
              child: Column(children: [
                Expanded(child: Center(child: AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c)))),
                VideoProgressIndicator(_c, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(
                      iconSize: 44,
                      color: Colors.white,
                      icon: Icon(_c.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                      onPressed: () => _c.value.isPlaying ? _c.pause() : _c.play(),
                    ),
                    Text('${MediaFiles.fmtDur(_c.value.position.inSeconds)} / ${MediaFiles.fmtDur(_c.value.duration.inSeconds)}',
                        style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
              ]),
            ),
    );
  }
}
