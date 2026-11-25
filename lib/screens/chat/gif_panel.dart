import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../data/api.dart';
import '../../data/media.dart';
import '../../theme/app_theme.dart';

class _Gif {
  final String id, url, thumb;
  final int w, h;
  _Gif(Map<String, dynamic> j)
      : id = j['id'] as String,
        url = j['url'] as String,
        thumb = j['thumb'] as String,
        w = (j['w'] as num?)?.toInt() ?? 0,
        h = (j['h'] as num?)?.toInt() ?? 0;
}

/// GIF and sticker search (powered by KLIPY), plus "from your phone".
/// [onSend] gets a local file; [sticker] says whether to send it as a sticker.
class GifPanel extends StatefulWidget {
  final void Function(String path, {required bool sticker}) onSend;
  final VoidCallback onPickFromPhone;
  const GifPanel({super.key, required this.onSend, required this.onPickFromPhone});
  @override
  State<GifPanel> createState() => _GifPanelState();
}

class _GifPanelState extends State<GifPanel> {
  final _q = TextEditingController();
  final _scroll = ScrollController();
  bool _stickers = false;
  List<_Gif> _items = [];
  bool _loading = false, _more = false, _off = false;
  String? _error, _sending;
  int _page = 1;
  Timer? _debounce;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(() {
      if (_more && !_loading && _scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    final gen = reset ? ++_gen : _gen;
    if (reset) _page = 1;
    setState(() => _loading = true);
    try {
      final q = Uri.encodeQueryComponent(_q.text.trim());
      final d = await Api.instance.request('GET', '/v1/gifs?kind=${_stickers ? 'stickers' : 'gifs'}&page=$_page&q=$q');
      if (!mounted || gen != _gen) return;
      final got = [for (final x in (d['items'] as List? ?? [])) _Gif((x as Map).cast<String, dynamic>())];
      setState(() {
        _items = reset ? got : [..._items, ...got];
        _more = d['more'] == true;
        _page++;
        _error = null;
        _off = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _off = e is ApiException && e.code == 'GIFS_OFF';
        _error = e is ApiException ? e.message : "Couldn't load GIFs";
      });
    } finally {
      if (mounted && gen == _gen) setState(() => _loading = false);
    }
  }

  Future<void> _pick(_Gif g) async {
    if (_sending != null) return;
    setState(() => _sending = g.id);
    try {
      final r = await http.get(Uri.parse(g.url)).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) throw Exception();
      final dir = await MediaFiles.dir();
      final ext = g.url.toLowerCase().contains('.webp') ? 'webp' : 'gif';
      final f = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_klipy.$ext');
      await f.writeAsBytes(r.bodyBytes);
      widget.onSend(f.path, sticker: _stickers);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't send. Check your internet.")));
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    Widget body;
    if (_off) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.gif_box_outlined, size: 48, color: bc.muted),
          const SizedBox(height: 8),
          Text('Send a GIF saved on your phone', style: TextStyle(color: bc.muted)),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: widget.onPickFromPhone, icon: const Icon(Icons.folder_open_rounded), label: const Text('Choose GIF')),
        ]),
      );
    } else if (_error != null && _items.isEmpty) {
      body = Center(child: TextButton(onPressed: () => _load(reset: true), child: Text('$_error  ·  Retry')));
    } else if (_items.isEmpty && _loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_items.isEmpty) {
      body = Center(child: Text('Nothing found', style: TextStyle(color: bc.muted)));
    } else {
      body = GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(4),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _stickers ? 4 : 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final g = _items[i];
          return GestureDetector(
            onTap: () => _pick(g),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(fit: StackFit.expand, children: [
                if (!_stickers) ColoredBox(color: bc.raised),
                Image.network(
                  g.thumb,
                  fit: _stickers ? BoxFit.contain : BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: bc.muted),
                ),
                if (_sending == g.id)
                  const ColoredBox(color: Colors.black38, child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)))),
              ]),
            ),
          );
        },
      );
    }
    return ColoredBox(
      color: bc.bg,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _q,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
                  },
                  onSubmitted: (_) => _load(reset: true),
                  style: TextStyle(color: bc.text, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: bc.raised,
                    prefixIcon: Icon(Icons.search_rounded, color: bc.muted, size: 20),
                    hintText: _stickers ? 'Search stickers' : 'Search GIFs',
                    hintStyle: TextStyle(color: bc.muted),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [ButtonSegment(value: false, label: Text('GIF')), ButtonSegment(value: true, label: Text('Sticker'))],
              selected: {_stickers},
              onSelectionChanged: (v) {
                setState(() {
                  _stickers = v.first;
                  _items = [];
                });
                _load(reset: true);
              },
            ),
            IconButton(onPressed: widget.onPickFromPhone, tooltip: 'From your phone', icon: Icon(Icons.folder_open_rounded, color: bc.muted)),
          ]),
        ),
        Expanded(child: body),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text('Powered by KLIPY', style: TextStyle(fontSize: 10.5, color: bc.muted)),
        ),
      ]),
    );
  }
}
