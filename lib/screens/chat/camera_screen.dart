import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../data/media.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import 'chat_tools.dart';

/// What the camera hands back to the chat.
class CameraShot {
  final String path;
  final bool video;
  final String caption;
  final bool once;
  final bool note; // round "video note"
  const CameraShot(this.path, {this.video = false, this.caption = '', this.once = false, this.note = false});
}

enum _Mode { video, photo, note }

/// WhatsApp-style camera: live preview, recent photos strip, gallery grid,
/// flash, flip, Video / Photo / Video note, hold the shutter to record,
/// then filters + caption before sending.
class CameraScreen extends StatefulWidget {
  final String to;
  const CameraScreen({super.key, required this.to});

  static Future<List<CameraShot>?> open(BuildContext context, String to) =>
      Navigator.of(context).push<List<CameraShot>>(MaterialPageRoute(builder: (_) => CameraScreen(to: to)));

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cams = [];
  CameraController? _c;
  int _camIndex = 0;
  FlashMode _flash = FlashMode.off;
  _Mode _mode = _Mode.photo;
  bool _recording = false;
  DateTime? _recAt;
  Timer? _tick;
  String? _error;
  List<AssetEntity> _recent = [];
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _album;
  bool _gallery = false;
  // Photo mode: tap = photo, hold = video.
  Timer? _holdTimer;
  bool _pressing = false, _startingRec = false, _stopWhenStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    _loadRecent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _holdTimer?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (s == AppLifecycleState.inactive) {
      c.dispose();
      _c = null;
    } else if (s == AppLifecycleState.resumed) {
      _open(_cams[_camIndex]);
    }
  }

  Future<void> _start() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) throw Exception();
      _camIndex = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_camIndex < 0) _camIndex = 0;
      await _open(_cams[_camIndex]);
    } catch (_) {
      if (mounted) setState(() => _error = 'Allow camera access to take photos');
    }
  }

  Future<void> _open(CameraDescription d) async {
    final old = _c;
    _c = null;
    if (mounted) setState(() {});
    await old?.dispose();
    final c = CameraController(d, ResolutionPreset.high, enableAudio: true);
    try {
      await c.initialize();
      await c.setFlashMode(_flash);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
    } catch (_) {
      if (mounted) setState(() => _error = 'Allow camera and microphone access');
    }
  }

  Future<void> _loadRecent() async {
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.hasAccess) return;
      final paths = await PhotoManager.getAssetPathList(type: RequestType.common);
      if (paths.isEmpty) return;
      final all = paths.firstWhere((p) => p.isAll, orElse: () => paths.first);
      final list = await all.getAssetListPaged(page: 0, size: 300);
      if (mounted) {
        setState(() {
          _albums = paths;
          _album = all;
          _recent = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _openAlbum(AssetPathEntity a) async {
    final list = await a.getAssetListPaged(page: 0, size: 300);
    if (mounted) {
      setState(() {
        _album = a;
        _recent = list;
      });
    }
  }

  Future<void> _chooseAlbum() async {
    final picked = await showModalBottomSheet<AssetPathEntity>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (s) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final a in _albums)
            FutureBuilder<int>(
              future: a.assetCountAsync,
              builder: (_, n) => ListTile(
                leading: Icon(a.isAll ? Icons.photo_library_outlined : Icons.folder_outlined, color: Colors.white70),
                title: Text(a.isAll ? 'Recents' : a.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text('${n.data ?? ''} items', style: const TextStyle(color: Colors.white54)),
                trailing: a.id == _album?.id ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                onTap: () => Navigator.pop(s, a),
              ),
            ),
        ]),
      ),
    );
    if (picked != null) await _openAlbum(picked);
  }

  void _shutterDown() {
    if (_mode != _Mode.photo || _recording) return;
    _pressing = true;
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 350), () {
      if (_pressing) _startRec();
    });
  }

  void _shutterUp() {
    if (_mode != _Mode.photo) return;
    final wasPressing = _pressing;
    _pressing = false;
    _holdTimer?.cancel();
    if (_startingRec) {
      _stopWhenStarted = true;
    } else if (_recording) {
      _stopRec();
    } else if (wasPressing) {
      _photo();
    }
  }

  void _flip() {
    if (_cams.length < 2 || _recording) return;
    _camIndex = (_camIndex + 1) % _cams.length;
    _open(_cams[_camIndex]);
  }

  void _cycleFlash() {
    final next = switch (_flash) { FlashMode.off => FlashMode.auto, FlashMode.auto => FlashMode.always, _ => FlashMode.off };
    setState(() => _flash = next);
    _c?.setFlashMode(next).catchError((_) {});
  }

  Future<void> _photo() async {
    final c = _c;
    if (c == null || c.value.isTakingPicture) return;
    try {
      final f = await c.takePicture();
      await _review(f.path, video: false);
    } catch (_) {}
  }

  Future<void> _startRec() async {
    final c = _c;
    if (c == null || _recording || _startingRec) return;
    _startingRec = true;
    try {
      await c.prepareForVideoRecording();
      await c.startVideoRecording();
      setState(() {
        _recording = true;
        _recAt = DateTime.now();
      });
      _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => mounted ? setState(() {}) : null);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't start video. Allow microphone access.")));
    } finally {
      _startingRec = false;
    }
    if (_stopWhenStarted) {
      _stopWhenStarted = false;
      await _stopRec();
    }
  }

  Future<void> _stopRec() async {
    final c = _c;
    if (c == null || !_recording) return;
    _tick?.cancel();
    try {
      final f = await c.stopVideoRecording();
      setState(() => _recording = false);
      if (DateTime.now().difference(_recAt!).inMilliseconds < 800) return;
      await _review(f.path, video: true);
    } catch (_) {
      setState(() => _recording = false);
    }
  }

  Future<void> _review(String path, {required bool video}) async {
    if (video) {
      if (!mounted) return;
      if (_mode == _Mode.note) {
        Navigator.pop(context, [CameraShot(path, video: true, note: true)]);
        return;
      }
      final shot = await Navigator.of(context).push<CameraShot>(MaterialPageRoute(builder: (_) => VideoReviewScreen(path: path, to: widget.to)));
      if (shot != null && mounted) Navigator.pop(context, [shot]);
      return;
    }
    final shot = await Navigator.of(context).push<CameraShot>(MaterialPageRoute(builder: (_) => PhotoEditScreen(path: path, to: widget.to)));
    if (shot != null && mounted) Navigator.pop(context, [shot]);
  }

  Future<void> _pickAsset(AssetEntity a) async {
    final f = await a.file;
    if (f == null) return;
    if (a.type == AssetType.video) {
      if (!mounted) return;
      final shot = await Navigator.of(context).push<CameraShot>(MaterialPageRoute(builder: (_) => VideoReviewScreen(path: f.path, to: widget.to)));
      if (shot != null && mounted) Navigator.pop(context, [shot]);
    } else {
      await _review(f.path, video: false);
    }
  }

  String get _recTime {
    final s = _recAt == null ? 0 : DateTime.now().difference(_recAt!).inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _thumb(AssetEntity a, double size) => FutureBuilder<Uint8List?>(
        future: a.thumbnailDataWithSize(const ThumbnailSize.square(200)),
        builder: (_, s) => GestureDetector(
          onTap: () => _pickAsset(a),
          child: Stack(fit: StackFit.expand, children: [
            Container(color: Colors.white10, child: s.data == null ? null : Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true)),
            if (a.type == AssetType.video)
              Positioned(
                left: 4,
                bottom: 3,
                child: Text('${a.duration ~/ 60}:${(a.duration % 60).toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, shadows: [Shadow(blurRadius: 3)])),
              ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final note = _mode == _Mode.note;
    Widget preview;
    if (_error != null) {
      preview = Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)));
    } else if (c == null || !c.value.isInitialized) {
      preview = const Center(child: CircularProgressIndicator(color: Colors.white));
    } else {
      final p = Center(
        child: AspectRatio(aspectRatio: 1 / c.value.aspectRatio, child: CameraPreview(c)),
      );
      preview = note
          ? Center(
              child: ClipOval(
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.82,
                  height: MediaQuery.of(context).size.width * 0.82,
                  child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: 300, height: 300 * c.value.aspectRatio, child: CameraPreview(c))),
                ),
              ),
            )
          : p;
    }

    return PopScope(
      canPop: !_gallery,
      onPopInvokedWithResult: (did, _) {
        if (!did && _gallery) setState(() => _gallery = false);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // fit: expand — the Stack must fill the screen, or the controls end up at the top.
        body: Stack(fit: StackFit.expand, children: [
          Positioned.fill(child: preview),
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28)),
                const Spacer(),
                if (_recording)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                    child: Text(_recTime, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                const Spacer(),
                IconButton(
                  onPressed: _cycleFlash,
                  icon: Icon(
                    switch (_flash) { FlashMode.auto => Icons.flash_auto_rounded, FlashMode.always => Icons.flash_on_rounded, _ => Icons.flash_off_rounded },
                    color: Colors.white,
                  ),
                ),
              ]),
            ),
          ),
          ),
          // Bottom: recent strip, controls, modes
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_recent.isNotEmpty && !_recording && !note)
                  GestureDetector(
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) < -200) setState(() => _gallery = true);
                    },
                    child: SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        itemCount: _recent.length.clamp(0, 30),
                        separatorBuilder: (_, __) => const SizedBox(width: 3),
                        itemBuilder: (_, i) => SizedBox(width: 72, child: _thumb(_recent[i], 72)),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _round(Icons.photo_library_outlined, _recording ? null : () => setState(() => _gallery = true)),
                  GestureDetector(
                    // Video / Video note: tap to start, tap to stop.
                    onTap: _mode == _Mode.photo
                        ? null
                        : () {
                            if (_recording) {
                              _stopRec();
                            } else {
                              _startRec();
                            }
                          },
                    child: Listener(
                    // Photo: tap = photo, hold = video until you let go.
                    onPointerDown: (_) => _shutterDown(),
                    onPointerUp: (_) => _shutterUp(),
                    onPointerCancel: (_) => _shutterUp(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: _recording ? 88 : 76,
                      height: _recording ? 88 : 76,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                      padding: const EdgeInsets.all(5),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _recording || _mode != _Mode.photo ? Colors.red : Colors.white,
                          shape: _recording ? BoxShape.rectangle : BoxShape.circle,
                          borderRadius: _recording ? BorderRadius.circular(8) : null,
                        ),
                        margin: _recording ? const EdgeInsets.all(18) : EdgeInsets.zero,
                      ),
                    ),
                  ),
                  ),
                  _round(Icons.cameraswitch_rounded, _recording ? null : _flip),
                ]),
                const SizedBox(height: 14),
                if (!_recording)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final (m, label) in const [(_Mode.video, 'Video'), (_Mode.photo, 'Photo'), (_Mode.note, 'Video note')])
                      GestureDetector(
                        onTap: () => setState(() => _mode = m),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(color: _mode == m ? Colors.white24 : Colors.transparent, borderRadius: BorderRadius.circular(16)),
                          child: Text(label, style: TextStyle(color: Colors.white, fontWeight: _mode == m ? FontWeight.w700 : FontWeight.w500)),
                        ),
                      ),
                  ]),
                const SizedBox(height: 10),
              ]),
            ),
          ),
          if (_mode == _Mode.photo && !_recording && c != null)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 230,
              child: Text('Hold for video, tap for photo', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12.5, shadows: [Shadow(blurRadius: 4)])),
            ),
          // Gallery grid ("Recents"), slides up
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            top: _gallery ? 0 : MediaQuery.of(context).size.height,
            height: MediaQuery.of(context).size.height,
            child: Container(
              color: Colors.black,
              child: SafeArea(
                child: Column(children: [
                  Row(children: [
                    IconButton(onPressed: () => setState(() => _gallery = false), icon: const Icon(Icons.close_rounded, color: Colors.white)),
                    Expanded(
                      child: Center(
                        child: TextButton.icon(
                          onPressed: _albums.isEmpty ? null : _chooseAlbum,
                          iconAlignment: IconAlignment.end,
                          icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white),
                          label: Text(_album == null || _album!.isAll ? 'Recents' : _album!.name,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ]),
                  Expanded(
                    child: _recent.isEmpty
                        ? const Center(child: Text('Allow photos access to see your gallery', style: TextStyle(color: Colors.white60)))
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
                            itemCount: _recent.length,
                            itemBuilder: (_, i) => _thumb(_recent[i], 100),
                          ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _round(IconData i, VoidCallback? onTap) => Material(
        color: Colors.black38,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(12), child: Icon(i, color: Colors.white, size: 26)),
        ),
      );
}

// ======================================================================= video review
class VideoReviewScreen extends StatefulWidget {
  final String path;
  final String to;
  const VideoReviewScreen({super.key, required this.path, required this.to});
  @override
  State<VideoReviewScreen> createState() => _VideoReviewScreenState();
}

class _VideoReviewScreenState extends State<VideoReviewScreen> {
  late final VideoPlayerController _v = VideoPlayerController.file(File(widget.path));
  final _caption = TextEditingController();

  @override
  void initState() {
    super.initState();
    _v.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _v.setLooping(true);
      _v.play();
    });
    _v.addListener(() => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
            const Spacer(),
          ]),
          Expanded(
            child: GestureDetector(
              onTap: () => _v.value.isPlaying ? _v.pause() : _v.play(),
              child: Center(
                child: _v.value.isInitialized
                    ? Stack(alignment: Alignment.center, children: [
                        AspectRatio(aspectRatio: _v.value.aspectRatio, child: VideoPlayer(_v)),
                        if (!_v.value.isPlaying) const Icon(Icons.play_circle_fill_rounded, size: 72, color: Colors.white70),
                      ])
                    : const CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Row(children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(26)),
                  child: TextField(
                    controller: _caption,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(border: InputBorder.none, hintText: 'Add a caption…', hintStyle: TextStyle(color: Colors.white54)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton(
                heroTag: 'vid-send',
                onPressed: () => Navigator.pop(context, CameraShot(widget.path, video: true, caption: _caption.text.trim())),
                child: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(widget.to, style: const TextStyle(color: Colors.white60, fontSize: 12.5))),
        ]),
      ),
    );
  }
}

// ======================================================================= edit + send
/// Photo filters (colour matrices), like WhatsApp's "Filters".
const _filters = <(String, List<double>?)>[
  ('None', null),
  ('Pop', [1.25, 0, 0, 0, -10, 0, 1.25, 0, 0, -10, 0, 0, 1.25, 0, -10, 0, 0, 0, 1, 0]),
  ('B&W', [0.33, 0.59, 0.11, 0, 0, 0.33, 0.59, 0.11, 0, 0, 0.33, 0.59, 0.11, 0, 0, 0, 0, 0, 1, 0]),
  ('Cool', [0.9, 0, 0, 0, 0, 0, 1.0, 0, 0, 5, 0, 0, 1.2, 0, 15, 0, 0, 0, 1, 0]),
  ('Warm', [1.15, 0, 0, 0, 12, 0, 1.0, 0, 0, 4, 0, 0, 0.85, 0, -8, 0, 0, 0, 1, 0]),
  ('Chrome', [1.1, 0.05, 0, 0, -5, 0.05, 1.1, 0, 0, -5, 0, 0.05, 1.1, 0, -5, 0, 0, 0, 1, 0]),
  ('Film', [0.9, 0.1, 0.05, 0, 10, 0.05, 0.85, 0.1, 0, 10, 0.05, 0.1, 0.8, 0, 12, 0, 0, 0, 1, 0]),
  ('Sepia', [0.39, 0.77, 0.19, 0, 0, 0.35, 0.69, 0.17, 0, 0, 0.27, 0.53, 0.13, 0, 0, 0, 0, 0, 1, 0]),
];

class PhotoEditScreen extends StatefulWidget {
  final String path;
  final String to;
  const PhotoEditScreen({super.key, required this.path, required this.to});
  @override
  State<PhotoEditScreen> createState() => _PhotoEditScreenState();
}

class _PhotoEditScreenState extends State<PhotoEditScreen> {
  final _caption = TextEditingController();
  int _filter = 0;
  bool _once = false;
  bool _showFilters = false;
  bool _busy = false;

  Future<String> _applyFilter() async {
    final m = _filters[_filter].$2;
    if (m == null) return widget.path;
    final bytes = await File(widget.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 2048);
    final img = (await codec.getNextFrame()).image;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawImage(img, Offset.zero, Paint()..colorFilter = ColorFilter.matrix(m));
    final out = await rec.endRecording().toImage(img.width, img.height);
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/filtered_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(png!.buffer.asUint8List());
    return f.path;
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final p = await _applyFilter();
    if (mounted) Navigator.pop(context, CameraShot(p, caption: _caption.text.trim(), once: _once));
  }

  @override
  Widget build(BuildContext context) {
    final m = _filters[_filter].$2;
    Widget img = Image.file(File(widget.path), fit: BoxFit.contain);
    if (m != null) img = ColorFiltered(colorFilter: ColorFilter.matrix(m), child: img);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _showFilters = !_showFilters),
              icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
              label: const Text('Filters', style: TextStyle(color: Colors.white)),
            ),
          ]),
          Expanded(child: GestureDetector(onVerticalDragEnd: (_) => setState(() => _showFilters = !_showFilters), child: Center(child: img))),
          if (_showFilters)
            SizedBox(
              height: 96,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemBuilder: (_, i) {
                  final fm = _filters[i].$2;
                  Widget t = Image.file(File(widget.path), width: 62, height: 62, fit: BoxFit.cover, cacheWidth: 160);
                  if (fm != null) t = ColorFiltered(colorFilter: ColorFilter.matrix(fm), child: t);
                  return GestureDetector(
                    onTap: () => setState(() => _filter = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _filter == i ? Colors.white : Colors.transparent, width: 2),
                          ),
                          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: t),
                        ),
                        const SizedBox(height: 4),
                        Text(_filters[i].$1, style: TextStyle(color: _filter == i ? Colors.white : Colors.white60, fontSize: 11.5)),
                      ]),
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Row(children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(26)),
                  child: Row(children: [
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _caption,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 4,
                        minLines: 1,
                        decoration: const InputDecoration(border: InputBorder.none, hintText: 'Add a caption…', hintStyle: TextStyle(color: Colors.white54)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'View once',
                      onPressed: () => setState(() => _once = !_once),
                      icon: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: _once ? Colors.white : Colors.transparent, border: Border.all(color: Colors.white, width: 1.6)),
                        child: Center(child: Text('1', style: TextStyle(color: _once ? Colors.black : Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton(
                heroTag: 'cam-send',
                onPressed: _busy ? null : _send,
                child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.send_rounded),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(widget.to, style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
          ),
        ]),
      ),
    );
  }
}

/// Home screen camera button: take a photo / video, then pick who gets it.
Future<void> cameraToChats(BuildContext context) async {
  final shots = await CameraScreen.open(context, 'Send to…');
  if (shots == null || shots.isEmpty || !context.mounted) return;
  // Keep the files in BAATLY's media folder (camera files are temporary).
  final dir = await MediaFiles.dir();
  final kept = <String>[];
  for (final s in shots) {
    final ext = s.path.split('.').last;
    final dest = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await File(s.path).copy(dest);
    kept.add(dest);
  }
  if (!context.mounted) return;
  await pickChatsAndSend(context, (c) {
    for (final (i, s) in shots.indexed) {
      Messenger.instance.sendMedia(
        c,
        path: kept[i],
        kind: s.video ? MsgKind.video : MsgKind.image,
        caption: s.caption,
        name: s.video ? 'video.mp4' : 'photo.jpg',
        once: s.once,
        extra: {if (s.note) 'note': true},
      );
    }
  });
}
