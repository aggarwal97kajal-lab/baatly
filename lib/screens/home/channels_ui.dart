import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/app_state.dart';
import '../../data/api.dart';
import '../../data/channels.dart';
import '../../data/media.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import '../chat/links.dart';

String _when(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final d = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  if (d == today) return hhmm(t);
  if (today.difference(d).inDays == 1) return 'Yesterday';
  return '${t.day}/${t.month}/${t.year % 100}';
}

String _count(int n) => n >= 1000000 ? '${(n / 1000000).toStringAsFixed(1)}M' : n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : '$n';

class _ChannelAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _ChannelAvatar({required this.name, this.size = 50});

  @override
  Widget build(BuildContext context) {
    final i = name.codeUnits.fold<int>(0, (a, b) => a + b) % Mitti.avatarColors.length;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Mitti.avatarColors[i], borderRadius: BorderRadius.circular(size * 0.3)),
      alignment: Alignment.center,
      child: Text(name.isEmpty ? '#' : name.characters.first.toUpperCase(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.4)),
    );
  }
}

/// "Channels" block under statuses in the Updates tab.
class ChannelsSection extends StatefulWidget {
  const ChannelsSection({super.key});

  @override
  State<ChannelsSection> createState() => _ChannelsSectionState();
}

class _ChannelsSectionState extends State<ChannelsSection> {
  @override
  void initState() {
    super.initState();
    unawaited(ChannelService.instance.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return ListenableBuilder(
      listenable: ChannelService.instance,
      builder: (context, _) {
        final list = ChannelService.instance.mine;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 12, 4),
            child: Row(children: [
              Expanded(child: Text('Channels', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: bc.text))),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExploreChannelsScreen())),
                child: const Text('Explore'),
              ),
              IconButton(
                tooltip: 'Create channel',
                icon: Icon(Icons.add_rounded, color: bc.text),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewChannelScreen())),
              ),
            ]),
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Follow channels to get updates on topics you care about.', style: TextStyle(color: bc.muted, fontSize: 13.5)),
            ),
          for (final c in list)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 2),
              leading: _ChannelAvatar(name: c.name),
              title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: bc.text)),
              subtitle: Text(c.lastText.isEmpty ? (c.mine ? 'Your channel · ${_count(c.followers)} followers' : '${_count(c.followers)} followers') : c.lastText.replaceAll('\n', ' '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: bc.muted)),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_when(c.lastPost), style: TextStyle(fontSize: 12, color: ChannelService.instance.unread(c) > 0 ? context.primary : bc.muted)),
                if (ChannelService.instance.unread(c) > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: context.primary, shape: BoxShape.circle),
                  ),
              ]),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChannelScreen(id: c.id, name: c.name))),
            ),
        ]);
      },
    );
  }
}

class ExploreChannelsScreen extends StatefulWidget {
  const ExploreChannelsScreen({super.key});

  @override
  State<ExploreChannelsScreen> createState() => _ExploreChannelsScreenState();
}

class _ExploreChannelsScreenState extends State<ExploreChannelsScreen> {
  List<Channel>? _list;
  Timer? _deb;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await ChannelService.instance.explore(_q);
      if (mounted) setState(() => _list = l);
    } catch (_) {
      if (mounted) setState(() => _list = []);
    }
  }

  @override
  void dispose() {
    _deb?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Scaffold(
      backgroundColor: bc.bg,
      appBar: AppBar(title: const Text('Explore channels')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (v) {
              _q = v.trim();
              _deb?.cancel();
              _deb = Timer(const Duration(milliseconds: 350), _load);
            },
            decoration: InputDecoration(
              hintText: 'Search channels',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: bc.raised,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        Expanded(
          child: _list == null
              ? const Center(child: CircularProgressIndicator())
              : _list!.isEmpty
                  ? Center(child: Text(_q.isEmpty ? 'No channels yet. Create the first one!' : 'No channels found', style: TextStyle(color: bc.muted)))
                  : ListView(children: [
                      for (final c in _list!)
                        ListTile(
                          leading: _ChannelAvatar(name: c.name, size: 46),
                          title: Text(c.name, style: TextStyle(fontWeight: FontWeight.w700, color: bc.text)),
                          subtitle: Text('${_count(c.followers)} followers${c.description.isEmpty ? '' : ' · ${c.description}'}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: bc.muted)),
                          trailing: c.following
                              ? Icon(Icons.check_circle_rounded, color: context.primary)
                              : FilledButton.tonal(
                                  style: FilledButton.styleFrom(minimumSize: const Size(80, 36)),
                                  onPressed: () async {
                                    await ChannelService.instance.follow(c.id, true);
                                    setState(() => c.following = true);
                                  },
                                  child: const Text('Follow'),
                                ),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChannelScreen(id: c.id, name: c.name))),
                        ),
                    ]),
        ),
      ]),
    );
  }
}

class NewChannelScreen extends StatefulWidget {
  const NewChannelScreen({super.key});

  @override
  State<NewChannelScreen> createState() => _NewChannelScreenState();
}

class _NewChannelScreenState extends State<NewChannelScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().length < 2) return;
    setState(() => _busy = true);
    try {
      final c = await ChannelService.instance.create(_name.text.trim(), _desc.text.trim());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChannelScreen(id: c.id, name: c.name)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : "Couldn't create. Check your connection.")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Scaffold(
      backgroundColor: bc.bg,
      appBar: AppBar(title: const Text('New channel')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Anyone can find and follow your channel. Only you can post. Followers see your posts but not each other.',
            style: TextStyle(color: bc.muted, height: 1.4)),
        const SizedBox(height: 18),
        TextField(controller: _name, maxLength: 60, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Channel name')),
        TextField(controller: _desc, maxLength: 500, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)')),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy || _name.text.trim().length < 2 ? null : _create, child: Text(_busy ? 'Creating…' : 'Create channel')),
      ]),
    );
  }
}

class ChannelScreen extends StatefulWidget {
  final String id;
  final String name;
  const ChannelScreen({super.key, required this.id, required this.name});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  Channel? _ch;
  List<ChannelPost> _posts = [];
  String? _error;
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    ChannelService.instance.listen(widget.id, _load);
  }

  @override
  void dispose() {
    ChannelService.instance.unlisten(widget.id);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final (c, p) = await ChannelService.instance.open(widget.id);
      if (!mounted) return;
      setState(() {
        _ch = c;
        _posts = p;
        _error = null;
      });
      unawaited(ChannelService.instance.markSeen(widget.id));
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : "Couldn't load. Pull to try again.");
    }
  }

  Future<void> _post({String? photo}) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && photo == null) return;
    setState(() => _sending = true);
    try {
      Map<String, dynamic>? media;
      if (photo != null) media = await Messenger.instance.uploadForChannel(photo);
      await ChannelService.instance.post(widget.id, text, media: media);
      _ctrl.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : "Couldn't post. Check your connection.")));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _react(ChannelPost p) async {
    final mine = p.reactions.where((r) => r.mine).map((r) => r.e).firstOrNull;
    final e = await showModalBottomSheet<String>(
      context: context,
      builder: (sh) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final x in const ['👍', '❤️', '😂', '😮', '😢', '🙏', '🔥'])
              GestureDetector(
                onTap: () => Navigator.pop(sh, x),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: x == mine ? context.primary.withOpacity(0.2) : null, shape: BoxShape.circle),
                  child: Text(x, style: const TextStyle(fontSize: 30)),
                ),
              ),
          ]),
        ),
      ),
    );
    if (e == null) return;
    try {
      await ChannelService.instance.react(widget.id, p.id, e == mine ? null : e);
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final c = _ch;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          _ChannelAvatar(name: c?.name ?? widget.name, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c?.name ?? widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: bc.text)),
              if (c != null) Text('${_count(c.followers)} followers', style: TextStyle(fontSize: 12, color: bc.muted)),
            ]),
          ),
        ]),
        actions: [
          if (c != null)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'info') {
                  await showDialog<void>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: Text(c.name),
                      content: Text(c.description.isEmpty ? 'No description' : c.description),
                      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
                    ),
                  );
                } else if (v == 'unfollow') {
                  await ChannelService.instance.follow(c.id, false);
                  await _load();
                } else if (v == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Delete this channel?'),
                      content: const Text('All posts are removed for everyone. This can\'t be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await ChannelService.instance.delete(c.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'info', child: Text('Channel info')),
                if (c.following && !c.mine) const PopupMenuItem(value: 'unfollow', child: Text('Unfollow')),
                if (c.mine) const PopupMenuItem(value: 'delete', child: Text('Delete channel')),
              ],
            ),
        ],
      ),
      body: ChatBackground(
        child: Column(children: [
          Expanded(
            child: _error != null && c == null
                ? Center(child: Text(_error!, style: TextStyle(color: bc.muted)))
                : c == null
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _posts.isEmpty
                            ? ListView(children: [
                                const SizedBox(height: 120),
                                Center(child: Text(c.mine ? 'Write your first update below' : 'No updates yet', style: TextStyle(color: bc.muted))),
                              ])
                            : ListView.builder(
                                reverse: true,
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                                itemCount: _posts.length,
                                itemBuilder: (_, i) => _PostBubble(
                                  post: _posts[i],
                                  owner: c.mine,
                                  onReact: () => _react(_posts[i]),
                                  onDelete: () async {
                                    await ChannelService.instance.deletePost(widget.id, _posts[i].id);
                                    await _load();
                                  },
                                ),
                              ),
                      ),
          ),
          if (c != null && c.mine)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(color: bc.surface, borderRadius: BorderRadius.circular(26)),
                      child: Row(children: [
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            minLines: 1,
                            maxLines: 5,
                            decoration: const InputDecoration(hintText: 'Update', border: InputBorder.none),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.photo_outlined, color: bc.muted),
                          onPressed: _sending
                              ? null
                              : () async {
                                  final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
                                  if (x != null) await _post(photo: x.path);
                                },
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sending ? null : () => _post(),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(color: context.primary, gradient: bc.accentGradient, shape: BoxShape.circle),
                      child: _sending
                          ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(Icons.send_rounded, color: Theme.of(context).colorScheme.onPrimary),
                    ),
                  ),
                ]),
              ),
            )
          else if (c != null && !c.following)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                child: FilledButton(
                  onPressed: () async {
                    await ChannelService.instance.follow(c.id, true);
                    await _load();
                  },
                  child: const Text('Follow'),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _PostBubble extends StatefulWidget {
  final ChannelPost post;
  final bool owner;
  final VoidCallback onReact;
  final VoidCallback onDelete;
  const _PostBubble({required this.post, required this.owner, required this.onReact, required this.onDelete});

  @override
  State<_PostBubble> createState() => _PostBubbleState();
}

class _PostBubbleState extends State<_PostBubble> {
  String? _photo;

  @override
  void initState() {
    super.initState();
    final md = widget.post.media;
    if (md != null && md['id'] != null) _get(md);
  }

  Future<void> _get(Map<String, dynamic> md) async {
    final name = (md['name'] as String?) ?? 'photo.jpg';
    final ext = MediaFiles.ext(name);
    final f = File('${(await MediaFiles.dir()).path}/ch-${widget.post.id}${ext.isEmpty ? '' : '.$ext'}');
    if (await f.exists()) {
      if (mounted) setState(() => _photo = f.path);
      return;
    }
    final m = Message(id: 'ch-${widget.post.id}', text: '', fromMe: false, time: widget.post.at, kind: MsgKind.image, media: Map<String, dynamic>.from(md));
    final p = await Messenger.instance.downloadMedia(m);
    if (mounted && p != null) setState(() => _photo = p);
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final p = widget.post;
    final md = p.media;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: widget.owner
            ? () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Delete this update?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) widget.onDelete();
              }
            : null,
        onDoubleTap: widget.onReact,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          decoration: BoxDecoration(color: bc.inBubble, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (md != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _photo != null
                    ? Image.file(File(_photo!), fit: BoxFit.cover, width: double.infinity)
                    : AspectRatio(aspectRatio: 4 / 3, child: Container(color: bc.raised, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)))),
              ),
            if (p.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: LinkText(p.text, style: TextStyle(fontSize: 15, color: bc.text, height: 1.35), linkColor: context.primary),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.onReact,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      p.reactions.isEmpty ? '🙂 +' : p.reactions.map((r) => '${r.e} ${_count(r.n)}').join('  '),
                      style: TextStyle(fontSize: 12.5, color: bc.text),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(_when(p.at), style: TextStyle(fontSize: 11, color: bc.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
