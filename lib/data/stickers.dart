import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:path_provider/path_provider.dart';

/// Sticker files kept on this phone: the built-in BAATLY pack (drawn once on
/// first use) and the user's own stickers (made from photos or saved from chats).
class StickerStore extends ChangeNotifier {
  StickerStore._();
  static final instance = StickerStore._();

  List<String> mine = [];
  List<String> builtIn = [];
  bool _loaded = false;

  Future<Directory> _dir(String sub) async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/stickers/$sub');
    await d.create(recursive: true);
    return d;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final m = await _dir('mine');
    final files = m.listSync().whereType<File>().toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    mine = files.map((f) => f.path).toList();
    builtIn = await _ensureBuiltIn();
    notifyListeners();
  }

  /// Copies [src] into "My stickers". Returns the new path.
  Future<String> add(String src) async {
    final m = await _dir('mine');
    final dest = '${m.path}/${DateTime.now().millisecondsSinceEpoch}.png';
    await File(src).copy(dest);
    mine.insert(0, dest);
    notifyListeners();
    return dest;
  }

  Future<void> remove(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
    mine.remove(path);
    notifyListeners();
  }

  static const _pack = [
    '😂', '🤣', '😍', '🥰', '😘', '😎', '🤗', '🙏', '👍', '👌', '👏', '🙌',
    '❤️', '💔', '🔥', '🎉', '🎂', '🌹', '☕', '😴', '🤔', '🙄', '😢', '😭',
    '😡', '🥺', '😱', '🤯', '🥳', '😇', '🤝', '👋',
  ];

  Future<List<String>> _ensureBuiltIn() async {
    final d = await _dir('baatly_v2');
    final out = <String>[];
    for (var i = 0; i < _pack.length; i++) {
      final f = File('${d.path}/s$i.png');
      if (!f.existsSync() || f.lengthSync() == 0) {
        try {
          await f.writeAsBytes(await _draw(_pack[i]));
        } catch (_) {
          continue;
        }
      }
      out.add(f.path);
    }
    return out;
  }

  /// Draws one 512×512 transparent PNG sticker: a big emoji with a white
  /// die-cut outline, the classic sticker look. No text.
  static Future<List<int>> _draw(String emoji) async {
    const size = 512.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, const Rect.fromLTWH(0, 0, size, size));
    TextPainter p(Paint? fg) => TextPainter(
          text: TextSpan(text: emoji, style: TextStyle(fontSize: 330, foreground: fg)),
          textDirection: TextDirection.ltr,
        )..layout();
    final white = p(Paint()..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn));
    final normal = p(null);
    final o = Offset((size - normal.width) / 2, (size - normal.height) / 2);
    c.saveLayer(null, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 1, sigmaY: 1));
    for (var a = 0; a < 16; a++) {
      final r = a * 3.14159 * 2 / 16;
      white.paint(c, o + Offset(14 * _cos(r), 14 * _sin(r)));
    }
    c.restore();
    normal.paint(c, o);
    final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  static double _sin(double x) => math.sin(x);
  static double _cos(double x) => math.cos(x);

  /// Cuts the person/object out of a photo (on the phone, nothing uploaded),
  /// trims it, adds a white outline and returns a 512×512 PNG file path.
  /// Returns null when no clear subject is found.
  static Future<String?> cutOut(String src) async {
    final seg = SubjectSegmenter(
      options: SubjectSegmenterOptions(
        enableForegroundBitmap: true,
        enableForegroundConfidenceMask: false,
        enableMultipleSubjects: SubjectResultOptions(enableConfidenceMask: false, enableSubjectBitmap: false),
      ),
    );
    try {
      final r = await seg.processImage(InputImage.fromFilePath(src));
      final png = r.foregroundBitmap;
      if (png == null || png.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(png);
      final fg = (await codec.getNextFrame()).image;
      // Find the visible area so the sticker isn't mostly empty space.
      final px = (await fg.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var minX = fg.width, minY = fg.height, maxX = -1, maxY = -1;
      for (var y = 0; y < fg.height; y += 2) {
        for (var x = 0; x < fg.width; x += 2) {
          if (px.getUint8((y * fg.width + x) * 4 + 3) > 40) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
      if (maxX < 0 || (maxX - minX) < 20 || (maxY - minY) < 20) return null;
      const size = 512.0, pad = 26.0;
      final box = Rect.fromLTRB(minX.toDouble(), minY.toDouble(), maxX + 1.0, maxY + 1.0);
      final scale = (size - pad * 2) / (box.width > box.height ? box.width : box.height);
      final w = box.width * scale, h = box.height * scale;
      final dst = Rect.fromLTWH((size - w) / 2, (size - h) / 2, w, h);
      final rec = ui.PictureRecorder();
      final c = Canvas(rec, const Rect.fromLTWH(0, 0, size, size));
      final outline = Paint()
        ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn)
        ..filterQuality = FilterQuality.medium;
      for (var a = 0; a < 16; a++) {
        final r = a * 3.14159 * 2 / 16;
        c.drawImageRect(fg, box, dst.shift(Offset(9 * _cos(r), 9 * _sin(r))), outline);
      }
      c.drawImageRect(fg, box, dst, Paint()..filterQuality = FilterQuality.high);
      final out = await rec.endRecording().toImage(size.toInt(), size.toInt());
      final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
      final f = File('${Directory.systemTemp.path}/cut_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(bytes!.buffer.asUint8List());
      return f.path;
    } catch (_) {
      return null;
    } finally {
      await seg.close();
    }
  }
}

/// True when [t] is only 1–3 emoji (shown big, without a bubble, like WhatsApp).
bool isBigEmoji(String t) {
  final s = t.trim();
  if (s.isEmpty || s.length > 40) return false;
  for (final r in s.runes) {
    final ok = (r >= 0x1F000 && r <= 0x1FAFF) ||
        (r >= 0x2600 && r <= 0x27BF) ||
        (r >= 0x2300 && r <= 0x23FF) ||
        (r >= 0x2B00 && r <= 0x2BFF) ||
        (r >= 0x2190 && r <= 0x21FF) ||
        (r >= 0x25A0 && r <= 0x25FF) ||
        (r >= 0xE0020 && r <= 0xE007F) ||
        const {0x200D, 0xFE0F, 0x20E3, 0x3030, 0x303D, 0x3297, 0x3299, 0x00A9, 0x00AE, 0x2122, 0x2139, 0x2934, 0x2935}.contains(r);
    if (!ok) return false;
  }
  return s.characters.length <= 3;
}
