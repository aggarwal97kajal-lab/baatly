import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

/// Helpers for chat media files kept on this phone.
class MediaFiles {
  static Future<Directory> dir() async {
    final d = Directory('${(await getApplicationDocumentsDirectory()).path}/media');
    await d.create(recursive: true);
    return d;
  }

  static String ext(String name) {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  static String mime(String name) => switch (ext(name)) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        'doc' => 'application/msword',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls' => 'application/vnd.ms-excel',
        'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'ppt' => 'application/vnd.ms-powerpoint',
        'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'txt' => 'text/plain',
        'zip' => 'application/zip',
        'm4a' || 'aac' => 'audio/mp4',
        'mp3' => 'audio/mpeg',
        'mp4' => 'video/mp4',
        _ => 'application/octet-stream',
      };

  static String size(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Tiny blurred preview (base64 PNG) + original width/height.
  static Future<(String, int, int)?> thumb(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final full = await (await ui.instantiateImageCodec(bytes)).getNextFrame();
      final w = full.image.width, h = full.image.height;
      full.image.dispose();
      final small = await (await ui.instantiateImageCodec(bytes, targetWidth: 36)).getNextFrame();
      final png = await small.image.toByteData(format: ui.ImageByteFormat.png);
      small.image.dispose();
      if (png == null) return null;
      return (base64Encode(png.buffer.asUint8List()), w, h);
    } catch (_) {
      return null;
    }
  }

  static String fmtDur(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
