import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'chat_screen.dart';

/// New broadcast list (or change who's in one).
class BroadcastEditor extends StatefulWidget {
  final Chat? existing;
  const BroadcastEditor({super.key, this.existing});

  @override
  State<BroadcastEditor> createState() => _BroadcastEditorState();
}

class _BroadcastEditorState extends State<BroadcastEditor> {
  late final Set<String> _picked = {...?widget.existing?.members};
  late final _name = TextEditingController(text: widget.existing?.name ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<Chat> get _people => AppState.instance.chats.where((c) => c.peerId != null && c.isReal && !c.isNotes && !c.isBroadcast).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  void _done() {
    if (_picked.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick at least 2 people')));
      return;
    }
    final names = {for (final c in _people) c.peerId: c.name};
    final name = _name.text.trim().isNotEmpty
        ? _name.text.trim()
        : _picked.map((u) => names[u]?.split(' ').first ?? '').where((x) => x.isNotEmpty).take(3).join(', ');
    final ex = widget.existing;
    if (ex != null) {
      ex.name = name;
      Messenger.instance.setBroadcastMembers(ex, _picked.toList());
      Navigator.pop(context);
      return;
    }
    final chat = Messenger.instance.createBroadcast(name, _picked.toList());
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final people = _people;
    final byId = {for (final c in people) c.peerId!: c};
    return Scaffold(
      backgroundColor: bc.bg,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.existing == null ? 'New broadcast' : 'Broadcast list'),
          Text('${_picked.length} selected', style: TextStyle(fontSize: 12.5, color: bc.muted, fontWeight: FontWeight.w400)),
        ]),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: 'Delete list',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Delete broadcast list?'),
                    content: const Text('Messages already sent stay in each chat.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                AppState.instance.chats.remove(widget.existing);
                AppState.instance.changed();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: context.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        onPressed: _done,
        child: const Icon(Icons.check_rounded),
      ),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: TextField(controller: _name, maxLength: 40, decoration: const InputDecoration(labelText: 'List name (optional)')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Only people who are on BAATLY. Each gets your message in their own chat with you, and replies come only to you.',
              style: TextStyle(fontSize: 12.5, color: bc.muted)),
        ),
        if (_picked.isNotEmpty)
          SizedBox(
            height: 86,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14), children: [
              for (final u in _picked)
                if (byId[u] != null)
                  GestureDetector(
                    onTap: () => setState(() => _picked.remove(u)),
                    child: SizedBox(
                      width: 64,
                      child: Column(children: [
                        Avatar(initials: byId[u]!.initials, colorIndex: byId[u]!.colorIndex, photo: byId[u]!.photo, size: 46),
                        const SizedBox(height: 4),
                        Text(byId[u]!.name.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: bc.text)),
                      ]),
                    ),
                  ),
            ]),
          ),
        for (final c in people)
          CheckboxListTile(
            value: _picked.contains(c.peerId),
            onChanged: (v) => setState(() => v == true ? _picked.add(c.peerId!) : _picked.remove(c.peerId)),
            secondary: Avatar(initials: c.initials, colorIndex: c.colorIndex, photo: c.photo, size: 42),
            title: Text(c.name, style: TextStyle(color: bc.text)),
            subtitle: c.about.isEmpty ? null : Text(c.about, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: bc.muted)),
          ),
        const SizedBox(height: 90),
      ]),
    );
  }
}
