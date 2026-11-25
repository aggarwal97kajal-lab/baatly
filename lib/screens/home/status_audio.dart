import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/media.dart';

/// Pick a song / audio file from the phone and choose a 30-second part.
/// Returns {path, start (ms), dur (ms), name}.
Future<Map<String, dynamic>?> pickStatusAudio(BuildContext context) async {
  FilePickerResult? r;
  try {
    r = await FilePicker.platform.pickFiles(type: FileType.audio);
  } catch (_) {
    return null;
  }
  final f = r?.files.single;
  if (f?.path == null || !context.mounted) return null;
  return Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => _ClipScreen(path: f!.path!, name: f.name)));
}

class _ClipScreen extends StatefulWidget {
  final String path;
  final String name;
  const _ClipScreen({required this.path, required this.name});
  @override
  State<_ClipScreen> createState() => _ClipScreenState();
}

class _ClipScreenState extends State<_ClipScreen> {
  static const clipMs = 30000;
  final _p = AudioPlayer();
  Duration? _total;
  double _start = 0; // ms
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _p.setFilePath(widget.path).then((d) {
      if (mounted) setState(() => _total = d);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = "Couldn't open this audio file");
    });
    _p.playerStateStream.listen((s) {
      if (mounted) setState(() => _playing = s.playing && s.processingState != ProcessingState.completed);
    });
  }

  int get _dur {
    final t = _total?.inMilliseconds ?? clipMs;
    return (t - _start.round()).clamp(1000, clipMs);
  }

  Future<void> _preview() async {
    if (_playing) {
      await _p.pause();
      return;
    }
    await _p.setClip(start: Duration(milliseconds: _start.round()), end: Duration(milliseconds: _start.round() + _dur));
    await _p.seek(Duration.zero);
    await _p.play();
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _total?.inMilliseconds ?? 0;
    final maxStart = (total - 1000).clamp(0, 1 << 31).toDouble();
    return Scaffold(
      appBar: AppBar(title: const Text('Choose part of the song')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _error != null
            ? Center(child: Text(_error!))
            : _total == null
                ? const Center(child: CircularProgressIndicator())
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Icon(Icons.music_note_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(widget.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 24),
                    Text('Starts at ${MediaFiles.fmtDur(_start ~/ 1000)} · ${_dur ~/ 1000} sec', textAlign: TextAlign.center),
                    Slider(
                      value: _start.clamp(0, maxStart),
                      max: maxStart <= 0 ? 1 : maxStart,
                      onChanged: maxStart <= 0
                          ? null
                          : (v) {
                              setState(() => _start = v);
                              if (_playing) _p.pause();
                            },
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _preview,
                      icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      label: Text(_playing ? 'Pause' : 'Preview'),
                    ),
                    const Spacer(),
                    Text("Use music you have the right to share. Clips are up to 30 seconds.",
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, {'path': widget.path, 'start': _start.round(), 'dur': _dur, 'name': widget.name}),
                      child: const Text('Add to status'),
                    ),
                  ]),
      ),
    );
  }
}

/// Plays a status's audio clip while the slide is shown.
class StatusAudioPlayer {
  final _p = AudioPlayer();
  String? _current;

  Future<void> play(String path, int startMs, int durMs) async {
    try {
      if (_current != '$path@$startMs') {
        await _p.setFilePath(path);
        await _p.setClip(start: Duration(milliseconds: startMs), end: Duration(milliseconds: startMs + durMs));
        _current = '$path@$startMs';
      }
      await _p.seek(Duration.zero);
      await _p.play();
    } catch (_) {}
  }

  Future<void> pause() async {
    try {
      await _p.pause();
    } catch (_) {}
  }

  Future<void> resume() async {
    try {
      if (_current != null) await _p.play();
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _p.stop();
    } catch (_) {}
  }

  void dispose() => _p.dispose();
}
