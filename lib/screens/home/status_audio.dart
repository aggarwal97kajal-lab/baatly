import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import '../../data/media.dart';

/// Pick a song for a status, like WhatsApp's music: search a big song
/// library (Apple Music previews) or use a file from the phone, then choose
/// the part to play. Returns {path, start (ms), dur (ms), name}.
Future<Map<String, dynamic>?> pickStatusAudio(BuildContext context) =>
    Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const _MusicScreen()));

Future<Map<String, dynamic>?> _pickFromPhone(BuildContext context) async {
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

class _Song {
  final String title, artist, art, preview;
  _Song(Map<String, dynamic> j)
      : title = j['trackName'] as String? ?? '',
        artist = j['artistName'] as String? ?? '',
        art = (j['artworkUrl100'] as String? ?? '').replaceAll('100x100', '200x200'),
        preview = j['previewUrl'] as String? ?? '';
}

class _MusicScreen extends StatefulWidget {
  const _MusicScreen();
  @override
  State<_MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<_MusicScreen> {
  final _q = TextEditingController();
  final _player = AudioPlayer();
  List<_Song> _songs = [];
  bool _loading = true;
  String? _error;
  String? _playing;
  String? _busy;
  Timer? _debounce;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _trending();
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && mounted) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _player.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _trending() async {
    final g = ++_gen;
    setState(() => _loading = true);
    try {
      // Most played in India right now, then their previews.
      final rss = await http.get(Uri.parse('https://rss.applemarketingtools.com/api/v2/in/music/most-played/50/songs.json')).timeout(const Duration(seconds: 10));
      final ids = [for (final r in ((jsonDecode(rss.body)['feed'] as Map)['results'] as List)) (r as Map)['id']].join(',');
      final r = await http.get(Uri.parse('https://itunes.apple.com/lookup?country=in&id=$ids')).timeout(const Duration(seconds: 10));
      _show(g, r.body);
    } catch (_) {
      await _search('bollywood hits', g: g);
    }
  }

  Future<void> _search(String q, {int? g}) async {
    final gen = g ?? ++_gen;
    setState(() => _loading = true);
    try {
      final r = await http
          .get(Uri.parse('https://itunes.apple.com/search?media=music&entity=song&country=in&limit=50&term=${Uri.encodeQueryComponent(q)}'))
          .timeout(const Duration(seconds: 10));
      _show(gen, r.body);
    } catch (_) {
      if (mounted && gen == _gen) {
        setState(() {
          _loading = false;
          _error = "Couldn't load songs. Check your internet.";
        });
      }
    }
  }

  void _show(int gen, String body) {
    if (!mounted || gen != _gen) return;
    final list = [
      for (final x in ((jsonDecode(body) as Map)['results'] as List? ?? []))
        if ((x as Map)['previewUrl'] != null && x['wrapperType'] == 'track') _Song(x.cast<String, dynamic>())
    ];
    setState(() {
      _songs = list;
      _loading = false;
      _error = list.isEmpty ? 'No songs found' : null;
    });
  }

  Future<void> _toggle(_Song s) async {
    if (_playing == s.preview) {
      await _player.stop();
      setState(() => _playing = null);
      return;
    }
    setState(() => _playing = s.preview);
    try {
      await _player.setUrl(s.preview);
      await _player.play();
    } catch (_) {
      if (mounted) setState(() => _playing = null);
    }
  }

  Future<void> _pick(_Song s) async {
    await _player.stop();
    setState(() {
      _busy = s.preview;
      _playing = null;
    });
    try {
      final r = await http.get(Uri.parse(s.preview)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception();
      final dir = await MediaFiles.dir();
      final f = File('${dir.path}/song_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await f.writeAsBytes(r.bodyBytes);
      if (!mounted) return;
      final res = await Navigator.of(context).push<Map<String, dynamic>>(
          MaterialPageRoute(builder: (_) => _ClipScreen(path: f.path, name: '${s.title} · ${s.artist}', art: s.art)));
      if (res != null && mounted) Navigator.pop(context, res);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't get this song")));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Music')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 450), () => v.trim().isEmpty ? _trending() : _search(v.trim()));
            },
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search songs or artists',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
        ),
        ListTile(
          leading: CircleAvatar(backgroundColor: cs.primary.withOpacity(0.15), child: Icon(Icons.folder_open_rounded, color: cs.primary)),
          title: const Text('From your phone'),
          onTap: () async {
            await _player.stop();
            if (!context.mounted) return;
            final r = await _pickFromPhone(context);
            if (r != null && context.mounted) Navigator.pop(context, r);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_q.text.trim().isEmpty ? 'Trending in India' : 'Results',
                style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface.withOpacity(0.7))),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : ListView.builder(
                      itemCount: _songs.length,
                      itemBuilder: (_, i) {
                        final s = _songs[i];
                        final on = _playing == s.preview;
                        return ListTile(
                          onTap: _busy == null ? () => _pick(s) : null,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(s.art, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 50, height: 50, child: Icon(Icons.music_note_rounded))),
                          ),
                          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: _busy == s.preview
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                              : IconButton(
                                  onPressed: () => _toggle(s),
                                  icon: Icon(on ? Icons.pause_circle_filled_rounded : Icons.play_circle_outline_rounded, size: 32, color: cs.primary),
                                ),
                        );
                      },
                    ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Song previews from Apple Music', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ),
      ]),
    );
  }
}

class _ClipScreen extends StatefulWidget {
  final String path;
  final String name;
  final String? art;
  const _ClipScreen({required this.path, required this.name, this.art});
  @override
  State<_ClipScreen> createState() => _ClipScreenState();
}

class _ClipScreenState extends State<_ClipScreen> {
  static const clipMs = 15000; // like WhatsApp status music
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
