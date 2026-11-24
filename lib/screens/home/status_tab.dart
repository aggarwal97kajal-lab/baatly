import 'dart:async';
import 'dart:math' as math;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'status_privacy_screen.dart';
import '../../data/status_service.dart';
import '../../data/messenger.dart';

class StatusTab extends StatelessWidget {
  const StatusTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        bool hidden(StatusItem x) => x.ownerId != null && s.hiddenStatus.contains(x.ownerId);
        final fresh = s.statuses.where((x) => !x.seen && !hidden(x)).toList();
        final seen = s.statuses.where((x) => x.seen && !hidden(x)).toList();
        final hiddenList = s.statuses.where(hidden).toList();
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
            child: RefreshIndicator(
              onRefresh: () => StatusService.instance.refresh(),
              child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 8, 4),
                child: Row(children: [
                  Expanded(child: Text('Status', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: bc.text))),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: bc.text),
                    onSelected: (v) {
                      if (v == 'privacy') {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StatusPrivacyScreen()));
                      }
                    },
                    itemBuilder: (_) => const [PopupMenuItem(value: 'privacy', child: Text('Status privacy'))],
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Material(
                  color: bc.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                    leading: Stack(clipBehavior: Clip.none, children: [
                      _Ring(
                        segments: math.max(1, s.myStatuses.length),
                        active: s.myStatuses.isNotEmpty,
                        child: Avatar(initials: myName[0].toUpperCase(), colorIndex: 2, size: 44, photo: s.myPhoto),
                      ),
                      if (s.myStatuses.isEmpty)
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
                    subtitle: Text(s.myStatuses.isEmpty
                        ? 'Tap to add a status'
                        : s.myStatuses.any((x) => x.uploading)
                            ? 'Sending…'
                            : s.myStatuses.any((x) => x.failed)
                                ? "Couldn't send · tap ⋮ to retry"
                                : '${s.myStatuses.length} ${s.myStatuses.length == 1 ? 'update' : 'updates'} · ${statusAgo(s.myStatuses.last.at)}'),
                    trailing: s.myStatuses.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.more_vert_rounded), tooltip: 'My updates', onPressed: () => showMyUpdates(context)),
                    onTap: () {
                      if (s.myStatuses.isEmpty) {
                        pickPhotoStatus(context);
                      } else {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => StatusViewer(item: StatusItem(myName, myName[0], 2, 'My status', s.myStatuses), mine: true)));
                      }
                    },
                  ),
                ),
              ),
              if (fresh.isNotEmpty) ...[
                const SectionLabel('Recent updates'),
                SizedBox(
                  height: 150,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    children: [
                      for (final st in fresh) _StoryCard(item: st),
                      if (hiddenList.isNotEmpty) _HiddenCard(count: hiddenList.length, onTap: () => _showHidden(context, hiddenList)),
                    ],
                  ),
                ),
              ],
              if (seen.isNotEmpty) ...[
                const SectionLabel('Viewed updates'),
                for (final st in seen)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: _Ring(segments: st.slides.length, active: false, child: Avatar(initials: st.initials, colorIndex: st.colorIndex, size: 44, photo: ownerPhoto(st))),
                    title: Text(st.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(st.when),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatusViewer(item: st))),
                    onLongPress: () => askHideStatus(context, st),
                  ),
              ],
              if (fresh.isEmpty && hiddenList.isNotEmpty) ...[
                const SectionLabel('Hidden updates'),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  leading: CircleAvatar(radius: 26, backgroundColor: bc.raised, child: Icon(Icons.visibility_off_outlined, color: bc.muted)),
                  title: Text('${hiddenList.length} hidden', style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => _showHidden(context, hiddenList),
                ),
              ],
              const SizedBox(height: 90),
            ]),
            ),
          ),
        );
      },
    );
  }
}

String? ownerPhoto(StatusItem it) => it.ownerId == null ? null : Messenger.instance.photoOf(it.ownerId!);

/// Like WhatsApp: hide someone's statuses (they move to "Hidden").
Future<void> askHideStatus(BuildContext context, StatusItem item) async {
  final owner = item.ownerId;
  if (owner == null) return;
  final s = AppState.instance;
  final isHidden = s.hiddenStatus.contains(owner);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(isHidden ? "Unhide ${item.name}'s statuses?" : "Hide ${item.name}'s statuses?"),
      content: Text(isHidden
          ? "New statuses from ${item.name} will appear under recent updates again."
          : "New statuses from ${item.name} won't appear under recent updates anymore."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(d, true), child: Text(isHidden ? 'Unhide' : 'Hide')),
      ],
    ),
  );
  if (ok == true) s.setStatusHidden(owner, !isHidden);
}

void _showHidden(BuildContext context, List<StatusItem> list) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(alignment: Alignment.centerLeft, child: Text('Hidden updates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        ),
        for (final st in list)
          ListTile(
            leading: Avatar(initials: st.initials, colorIndex: st.colorIndex, size: 44, photo: ownerPhoto(st)),
            title: Text(st.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(st.when),
            trailing: TextButton(
              onPressed: () {
                Navigator.pop(sheet);
                AppState.instance.setStatusHidden(st.ownerId!, false);
              },
              child: const Text('Unhide'),
            ),
            onTap: () {
              Navigator.pop(sheet);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => StatusViewer(item: st)));
            },
          ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

class _HiddenCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _HiddenCard({required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 96,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bc.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: bc.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.visibility_off_outlined, color: bc.muted),
          const Spacer(),
          Text('Hidden', style: TextStyle(fontWeight: FontWeight.w700, color: bc.text)),
          Text('$count', style: TextStyle(fontSize: 12, color: bc.muted)),
        ]),
      ),
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
      onLongPress: () => askHideStatus(context, item),
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
            child: Avatar(initials: item.initials, colorIndex: item.colorIndex, size: 30, photo: ownerPhoto(item)),
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
  /// Own status: shows delete instead of reply.
  final bool mine;
  const StatusViewer({super.key, required this.item, this.mine = false});
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
    _markSeen();
  }

  void _markSeen() {
    if (widget.mine && _i < widget.item.slides.length) {
      unawaited(StatusService.instance.loadViewers(widget.item.slides[_i]));
      return;
    }
    if (widget.mine || _i >= widget.item.slides.length) return;
    StatusService.instance.viewed(widget.item, widget.item.slides[_i]);
  }

  Future<void> _showViews() async {
    final slide = widget.item.slides[_i];
    _c.stop();
    unawaited(StatusService.instance.loadViewers(slide));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => ListenableBuilder(
        listenable: AppState.instance,
        builder: (sheet, _) {
          final list = StatusService.instance.viewerList(slide);
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Viewed by ${slide.viewCount}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
              if (list.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('No views yet'))
              else
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final v in list)
                      ListTile(
                        leading: Avatar(initials: v.$1.isEmpty ? '#' : v.$1[0].toUpperCase(), colorIndex: v.$1.length % 7, size: 40, photo: v.$2),
                        title: Text(v.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(statusAgo(v.$3)),
                      ),
                  ]),
                ),
              const SizedBox(height: 8),
            ]),
          );
        },
      ),
    );
    if (mounted) _c.forward();
  }

  void _next() {
    if (_i < widget.item.slides.length - 1) {
      setState(() => _i++);
      _c.forward(from: 0);
      _markSeen();
    } else {
      if (!widget.mine) {
        widget.item.seen = true;
        AppState.instance.toggle(() {});
      }
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

  Future<void> _delete() async {
    _c.stop();
    final slide = widget.item.slides[_i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete this status update?'),
        content: const Text('It will be removed for everyone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete', style: TextStyle(color: Color(0xFFB3261E)))),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) {
      _c.forward();
      return;
    }
    AppState.instance.deleteMyStatus(slide);
    if (widget.item.slides.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _i = _i.clamp(0, widget.item.slides.length - 1));
    _c.forward(from: 0);
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
              leading: Avatar(initials: it.initials, colorIndex: it.colorIndex, size: 40, photo: widget.mine ? AppState.instance.myPhoto : ownerPhoto(it)),
              title: Text(it.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              subtitle: Text(widget.mine ? statusAgo(slide.at) : it.when, style: const TextStyle(color: Colors.white70)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (widget.mine)
                  IconButton(onPressed: _delete, tooltip: 'Delete', icon: const Icon(Icons.delete_outline_rounded, color: Colors.white)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
              ]),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: Mitti.medium,
                child: slide.isPhoto
                    ? Column(key: ValueKey('p$_i'), children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Center(child: Image.file(File(slide.imagePath!), fit: BoxFit.contain, filterQuality: FilterQuality.high)),
                          ),
                        ),
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
            if (widget.mine)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: slide.uploading
                    ? const Text('Sending…', style: TextStyle(color: Colors.white70))
                    : slide.failed
                        ? const Text("Couldn't send this update", style: TextStyle(color: Colors.white70))
                        : ListenableBuilder(
                            listenable: AppState.instance,
                            builder: (_, __) => TextButton.icon(
                              onPressed: slide.remoteId == null ? null : _showViews,
                              icon: const Icon(Icons.visibility_outlined, color: Colors.white),
                              label: Text('${slide.viewCount} ${slide.viewCount == 1 ? 'view' : 'views'}', style: const TextStyle(color: Colors.white)),
                            ),
                          ),
              ),
            if (!widget.mine)
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
                    final text = _reply.text.trim();
                    if (text.isEmpty) return;
                    _reply.clear();
                    FocusScope.of(context).unfocus();
                    if (widget.item.ownerId != null) {
                      StatusService.instance.reply(widget.item, slide, text);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply sent')));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply sent (demo)')));
                    }
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
  late String _path = widget.path;

  @override
  void initState() {
    super.initState();
    // Open the cropper straight away, like WhatsApp's editor.
    WidgetsBinding.instance.addPostFrameCallback((_) => _crop());
  }

  Future<void> _crop() async {
    try {
      final f = await ImageCropper().cropImage(
        sourcePath: _path,
        maxWidth: 1600,
        maxHeight: 1600,
        compressQuality: 80,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop & rotate',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            statusBarLight: false,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: Mitti.terracotta,
            lockAspectRatio: false,
            freeStyleCropEnabled: true,
            hideBottomControls: false,
            initAspectRatio: CropAspectRatioPreset.original,
            aspectRatioPresets: const [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
        ],
      );
      if (f != null && mounted) setState(() => _path = f.path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't open the cropper ($e)")));
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Discard', onPressed: () => Navigator.pop(context)),
        title: const Text('Photo status'),
        actions: [
          IconButton(icon: const Icon(Icons.crop_rotate_rounded), tooltip: 'Crop & rotate', onPressed: _crop),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(child: Image.file(File(_path), key: ValueKey(_path), fit: BoxFit.contain, width: double.infinity)),
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
                  AppState.instance.addMyStatus(StatusSlide.photo(_path, caption: _caption.text.trim()));
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


String statusAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return 'yesterday';
}

/// Small round preview of a status slide (photo or coloured text).
class StatusThumb extends StatelessWidget {
  final StatusSlide slide;
  final double size;
  const StatusThumb({super.key, required this.slide, this.size = 44});
  @override
  Widget build(BuildContext context) {
    if (slide.isPhoto) {
      return ClipOval(child: Image.file(File(slide.imagePath!), width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).round()));
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Color(slide.bg), shape: BoxShape.circle),
      child: Text(slide.text ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: size * 0.16, fontWeight: FontWeight.w700, height: 1.1)),
    );
  }
}

/// List of my own updates with delete buttons.
void showMyUpdates(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => ListenableBuilder(
      listenable: AppState.instance,
      builder: (sheet, _) {
        final s = AppState.instance;
        final list = s.myStatuses.reversed.toList();
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text('My updates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            ),
            if (list.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('No status updates')),
            for (final st in list)
              ListTile(
                leading: StatusThumb(slide: st, size: 44),
                title: Text(st.isPhoto ? ((st.caption ?? '').isEmpty ? 'Photo' : st.caption!) : (st.text ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(st.uploading
                    ? 'Sending…'
                    : st.failed
                        ? (StatusService.instance.lastError ?? "Couldn't send")
                        : '${statusAgo(st.at)} · ${st.viewCount} ${st.viewCount == 1 ? 'view' : 'views'}'),
                onTap: st.failed ? () => StatusService.instance.post(st) : null,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (st.failed)
                    IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'Retry', onPressed: () => StatusService.instance.post(st)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB3261E)),
                    tooltip: 'Delete',
                    onPressed: () => s.deleteMyStatus(st),
                  ),
                ]),
              ),
            ListTile(
              leading: CircleAvatar(backgroundColor: sheet.primary, child: const Icon(Icons.add_rounded, color: Colors.white)),
              title: const Text('Add status', style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(sheet);
                pickPhotoStatus(context);
              },
            ),
            const SizedBox(height: 8),
          ]),
        );
      },
    ),
  );
}
