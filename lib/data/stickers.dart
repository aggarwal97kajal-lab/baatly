import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
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
    ('😂', 'HAHA', 0xFFF4A261),
    ('🙏', 'THANK YOU', 0xFF2A9D8F),
    ('☀️', 'GOOD MORNING', 0xFFE9C46A),
    ('🌙', 'GOOD NIGHT', 0xFF3D5A80),
    ('❤️', 'LOVE YOU', 0xFFE63946),
    ('🥺', 'MISS YOU', 0xFF9D4EDD),
    ('🎉', 'CONGRATS!', 0xFFF77F00),
    ('🎂', 'HAPPY BIRTHDAY', 0xFFEF476F),
    ('👍', 'OK DONE', 0xFF06A77D),
    ('🤔', 'HMM...', 0xFF6C757D),
    ('😴', 'SLEEPY', 0xFF457B9D),
    ('🔥', 'AWESOME', 0xFFD62828),
    ('😎', 'COOL', 0xFF118AB2),
    ('🤗', 'HUGS', 0xFFC8553D),
    ('😡', 'ANGRY', 0xFFB5179E),
    ('👋', 'BYE BYE', 0xFF2E7D8C),
  ];

  Future<List<String>> _ensureBuiltIn() async {
    final d = await _dir('baatly_v1');
    final out = <String>[];
    for (var i = 0; i < _pack.length; i++) {
      final f = File('${d.path}/s$i.png');
      if (!f.existsSync() || f.lengthSync() == 0) {
        try {
          await f.writeAsBytes(await _draw(_pack[i].$1, _pack[i].$2, Color(_pack[i].$3)));
        } catch (_) {
          continue;
        }
      }
      out.add(f.path);
    }
    return out;
  }

  /// Draws one 512×512 transparent PNG sticker: big emoji, label on a pill,
  /// white outline — the classic sticker look.
  static Future<List<int>> _draw(String emoji, String label, Color color) async {
    const size = 512.0;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, const Rect.fromLTWH(0, 0, size, size));

    final emojiP = TextPainter(
      text: TextSpan(text: emoji, style: const TextStyle(fontSize: 250)),
      textDirection: TextDirection.ltr,
    )..layout();
    emojiP.paint(c, Offset((size - emojiP.width) / 2, 20));

    final textStyle = TextStyle(fontSize: label.length > 10 ? 46 : 58, fontWeight: FontWeight.w900, letterSpacing: 1.5);
    final tp = TextPainter(
      text: TextSpan(text: label, style: textStyle.copyWith(color: Colors.white)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size - 40);
    final w = tp.width + 56, h = tp.height + 26;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH((size - w) / 2, size - h - 26, w, h), Radius.circular(h / 2));
    c.drawRRect(r.inflate(8), Paint()..color = Colors.white);
    c.drawRRect(r, Paint()..color = color);
    tp.paint(c, Offset((size - tp.width) / 2, size - h - 26 + 13));

    final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }
}

/// True when [t] is only 1–3 emoji (shown big, without a bubble, like WhatsApp).
bool isBigEmoji(String t) {
  final s = t.trim();
  if (s.isEmpty || s.length > 40) return false;
  if (!RegExp(r'^(?:\p{Extended_Pictographic}|\p{Emoji_Modifier}|\p{Regional_Indicator}|‍|️|⃣)+$', unicode: true).hasMatch(s)) {
    return false;
  }
  return s.characters.length <= 3;
}
