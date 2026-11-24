import 'dart:math' as math;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';

class StatusTab extends StatelessWidget {
  const StatusTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final fresh = s.statuses.where((x) => !x.seen).toList();
        final seen = s.statuses.where((x) => x.seen).toList();
        final myName = s.name.isEmpty ? 'You' : s.name;
        return Scaffold(
          backgroundColor: bc.bg,
          floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
            FloatingActionButton.small(
              heroTag: 'st-text',
              backgroundColor: bc.raised,
              foregroundColor: bc.text,
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TextStatusScreen())),
              child: const Icon(Icons.edit_rounded),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'st-photo',
              backgroundColor: context.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              onPressed: () => pickPhotoStatus(context),
              child: const Icon(Icons.photo_camera_rounded),
            ),
          ]),
          body: SafeArea(
            child: ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                child: Text('Status', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: bc.text)),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: bc.surface, borderRadius: BorderRadius.circular(20)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: Stack(clipBehavior: Clip.none, children: [
                    _Ring(segments: math.max(1, s.myStatuses.length), active: s.myStatuses.isNotEmpty, child: Avatar(initials: myName[0].toUpperCase(), colorIndex: 2, size: 44)),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(color: context.primary, shape: BoxShape.circle, border: Border.all(color: bc.surface, width: 2)),
                        child: const Icon(Icons.add, size: 14, color: Colors.white),
                      ),
                    ),
                  ]),
                  title: const Text('My status', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(s.myStatuses.isEmpty ? 'Tap to add a status' : '${s.myStatuses.length} update · just now'),
                  onTap: () {
                    if (s.myStatuses.isEmpty) {
                      pickPhotoStatus(context);
                    } else {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => StatusViewer(item: StatusItem(myName, myName[0], 2, 'just now', s.myStatuses))));
                    }
                  },
                ),
              ),
              if (fresh.isNotEmpty) ...[
                const SectionLabel('Recent updates'),
                SizedBox(
                  height: 150,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [for (final st in fresh) _StoryCard(item: st)],
                  ),
                ),
              ],
              if (seen.isNotEmpty) ...[
                const SectionLabel('Viewed updates'),
                for (final st in seen)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: _Ring(segments: st.slides.length, active: false, child: Avatar(initials: st.initials, colorIndex: st.colorIndex, size: 44)),
                    title: Text(st.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(st.when),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatusViewer(item: st))),
                  ),
              ],
              const SizedBox(height: 90),
            ]),
          ),
        );
      },
    );
  }
}

class _StoryCard extends StatelessWidget {
  final StatusItem item;
  const _StoryCard({required this.item});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatusViewer(item: item))),
      child: Container(
        width: 96,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Color(item.slides.first.bg),
          borderRadius: BorderRadius.circular(16),
          image: item.slides.first.isPhoto
              ? DecorationImage(image: FileImage(File(item.slides.first.imagePath!)), fit: BoxFit.cover, opacity: 0.85)
              : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Ring(
            segments: item.slides.length,
            active: true,
            color: Colors.white,
            child: Avatar(initials: item.initials, colorIndex: item.colorIndex, size: 30),
          ),
          const Spacer(),
          Text(item.slides.first.text ?? item.slides.first.caption ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          const SizedBox(height: 4),
          Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final int segments;
  final bool active;
  final Widget child;
  final Color? color;
  const _Ring({required this.segments, required this.active, required this.child, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? (active ? context.primary : const Color(0xFFCDBBA8));
    return CustomPaint(
      painter: _RingPainter(segments, c),
      child: Padding(padding: const EdgeInsets.all(4), child: child),
    );
  }
}

class _RingPainter extends CustomPainter {
  final int n;
  final Color color;
  _RingPainter(this.n, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTWH(1.25, 1.25, size.width - 2.5, size.height - 2.5);
    final gap = n > 1 ? 0.18 : 0.0;
    final sweep = 2 * math.pi / n;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(rect, -math.pi / 2 + i * sweep + gap / 2, sweep - gap, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.n != n || old.color != color;
}

/// Full-screen status viewer with progress bars, tap to skip, hold to pause.
class StatusViewer extends StatefulWidget {
  final StatusItem item;
  const StatusViewer({super.key, required this.item});
  @override
  State<StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<StatusViewer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 5));
  int _i = 0;
  final _reply = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
    _c.forward();
  }

  void _next() {
    if (_i < widget.item.slides.length - 1) {
      setState(() => _i++);
      _c.forward(from: 0);
    } else {
      widget.item.seen = true;
      AppState.instance.toggle(() {});
      if (mounted) Navigator.pop(context);
    }
  }

  void _prev() {
    if (_i > 0) {
      setState(() => _i--);
      _c.forward(from: 0);
    } else {
      _c.forward(from: 0); // first story: just restart it
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final slide = it.slides[_i];
    final bg = Color(slide.bg);
    return Scaffold(
      backgroundColor: bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => d.globalPosition.dx < MediaQuery.of(context).size.width * 0.35 ? _prev() : _next(),
        onLongPressStart: (_) => _c.stop(),
        onLongPressEnd: (_) => _c.forward(),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => Row(
                  children: List.generate(it.slides.length, (k) {
                    final v = k < _i ? 1.0 : (k == _i ? _c.value : 0.0);
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        height: 3,
                        decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: v,
                          child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2))),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            ListTile(
              leading: Avatar(initials: it.initials, colorIndex: it.colorIndex, size: 40),
              title: Text(it.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              subtitle: Text(it.when, style: const TextStyle(color: Colors.white70)),
              trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: Mitti.medium,
                child: slide.isPhoto
                    ? Column(key: ValueKey('p$_i'), children: [
                        Expanded(child: Image.file(File(slide.imagePath!), fit: BoxFit.contain, width: double.infinity)),
                        if ((slide.caption ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                            child: Text(slide.caption!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                          ),
                      ])
                    : Center(
                        key: ValueKey('t$_i'),
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(slide.text ?? '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700, height: 1.3)),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _reply,
                    onTap: () => _c.stop(),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Reply…',
                      hintStyle: const TextStyle(color: Colors.white70),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Colors.white54)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: Colors.white)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    _reply.clear();
                    FocusScope.of(context).unfocus();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply sent (demo)')));
                    _c.forward();
                  },
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Create a text status: type, pick a colour, post.
class TextStatusScreen extends StatefulWidget {
  const TextStatusScreen({super.key});
  @override
  State<TextStatusScreen> createState() => _TextStatusScreenState();
}

class _TextStatusScreenState extends State<TextStatusScreen> {
  final _ctrl = TextEditingController();
  int _color = 0;
  static const _colors = [0xFFC8553D, 0xFF2A211C, 0xFF3E7C5A, 0xFF2E3A59, 0xFFB5651D, 0xFF7A5BA6];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Mitti.medium,
      color: Color(_colors[_color]),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    maxLines: null,
                    textAlign: TextAlign.center,
                    cursorColor: Colors.white,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Type a status…',
                      hintStyle: TextStyle(color: Colors.white60),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _colors.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _color = i),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(_colors[i]),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: i == _color ? 3 : 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(children: [
                const Expanded(
                  child: Text('Visible to my contacts · 24 hours', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                ),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  foregroundColor: Mitti.terracotta,
                  onPressed: _ctrl.text.trim().isEmpty
                      ? null
                      : () {
                          AppState.instance.addMyStatus(StatusSlide.text(_ctrl.text.trim(), _colors[_color]));
                          Navigator.pop(context);
                        },
                  child: const Icon(Icons.send_rounded),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}



/// Choose camera or gallery, then preview + caption + post.
Future<void> pickPhotoStatus(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Icon(Icons.photo_camera_outlined, color: ctx.primary),
          title: const Text('Take photo'),
          onTap: () => Navigator.pop(ctx, ImageSource.camera),
        ),
        ListTile(
          leading: Icon(Icons.photo_library_outlined, color: ctx.primary),
          title: const Text('Choose from gallery'),
          onTap: () => Navigator.pop(ctx, ImageSource.gallery),
        ),
        ListTile(
          leading: Icon(Icons.text_fields_rounded, color: ctx.primary),
          title: const Text('Text status'),
          onTap: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TextStatusScreen()));
          },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (source == null) return;
  XFile? file;
  try {
    file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 82);
  } catch (_) {
    if (context.mounted) showComingSoon(context, 'Camera permission needed');
    return;
  }
  if (file == null || !context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhotoStatusScreen(path: file!.path)));
}

class PhotoStatusScreen extends StatefulWidget {
  final String path;
  const PhotoStatusScreen({super.key, required this.path});
  @override
  State<PhotoStatusScreen> createState() => _PhotoStatusScreenState();
}

class _PhotoStatusScreenState extends State<PhotoStatusScreen> {
  final _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Photo status')),
      body: SafeArea(
        child: Column(children: [
          Expanded(child: Image.file(File(widget.path), fit: BoxFit.contain, width: double.infinity)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _caption,
                  maxLength: 200,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'Add a caption…',
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF222222),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FloatingActionButton(
                heroTag: 'st-send',
                backgroundColor: Mitti.terracotta,
                foregroundColor: Colors.white,
                onPressed: () {
                  AppState.instance.addMyStatus(StatusSlide.photo(widget.path, caption: _caption.text.trim()));
                  Navigator.pop(context);
                },
                child: const Icon(Icons.send_rounded),
              ),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Visible to my contacts · 24 hours', style: TextStyle(color: Colors.white60, fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}
