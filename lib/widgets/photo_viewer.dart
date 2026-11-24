import 'dart:io';

import 'package:flutter/material.dart';

/// Full-screen profile photo, pinch to zoom.
class PhotoViewerScreen extends StatelessWidget {
  final String path;
  final String title;
  final String? heroTag;
  const PhotoViewerScreen({super.key, required this.path, required this.title, this.heroTag});

  static void open(BuildContext context, String? path, String title, {String? heroTag}) {
    if (path == null) return;
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => PhotoViewerScreen(path: path, title: title, heroTag: heroTag),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final img = Image.file(File(path), fit: BoxFit.contain, filterQuality: FilterQuality.high);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: heroTag == null ? img : Hero(tag: heroTag!, child: img),
        ),
      ),
    );
  }
}
