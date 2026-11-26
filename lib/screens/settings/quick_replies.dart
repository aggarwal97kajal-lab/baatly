import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../theme/app_theme.dart';

/// Settings › Chats › Quick replies: saved texts you insert by typing "/shortcut" in a chat.
class QuickRepliesScreen extends StatelessWidget {
  const QuickRepliesScreen({super.key});

  Future<void> _edit(BuildContext context, [int? index]) async {
    final s = AppState.instance;
    final old = index == null ? null : s.quickReplies[index];
    final k = TextEditingController(text: old?['k'] ?? '');
    final t = TextEditingController(text: old?['t'] ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sh) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(sh).viewInsets.bottom + 20),
        child: StatefulBuilder(
          builder: (sh, set) {
            final key = k.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
            final taken = s.quickReplies.asMap().entries.any((e) => e.key != index && e.value['k'] == key);
            final ok = key.isNotEmpty && t.text.trim().isNotEmpty && !taken;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(index == null ? 'New quick reply' : 'Edit quick reply', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: k,
                maxLength: 20,
                onChanged: (_) => set(() {}),
                decoration: InputDecoration(
                  labelText: 'Shortcut',
                  prefixText: '/',
                  helperText: 'Letters and numbers only',
                  errorText: taken ? 'This shortcut is already used' : null,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: t,
                minLines: 2,
                maxLines: 6,
                maxLength: 1000,
                onChanged: (_) => set(() {}),
                decoration: const InputDecoration(labelText: 'Message'),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: ok ? () => Navigator.pop(sh, true) : null, child: const Text('Save')),
            ]);
          },
        ),
      ),
    );
    if (saved != true) return;
    final item = {'k': k.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9_]'), ''), 't': t.text.trim()};
    s.toggle(() {
      if (index == null) {
        s.quickReplies.add(item);
      } else {
        s.quickReplies[index] = item;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Quick replies')),
        floatingActionButton: FloatingActionButton(
          backgroundColor: context.primary,
          foregroundColor: Colors.white,
          onPressed: () => _edit(context),
          child: const Icon(Icons.add_rounded),
        ),
        body: s.quickReplies.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bolt_rounded, size: 56, color: context.primary),
                    const SizedBox(height: 12),
                    Text('Save texts you send again and again', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: bc.text)),
                    const SizedBox(height: 8),
                    Text('Then type "/" in any chat to pick one. Example: /addr for your address.',
                        textAlign: TextAlign.center, style: TextStyle(color: bc.muted, height: 1.4)),
                  ]),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: s.quickReplies.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: bc.line),
                itemBuilder: (context, i) {
                  final q = s.quickReplies[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
                    title: Text('/${q['k']}', style: TextStyle(color: context.primary, fontWeight: FontWeight.w700)),
                    subtitle: Text(q['t'] ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: bc.text, height: 1.35)),
                    onTap: () => _edit(context, i),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: bc.muted),
                      onPressed: () => s.toggle(() => s.quickReplies.removeAt(i)),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Quick replies matching what's typed ("/" or "/ad"), or empty.
List<Map<String, String>> quickRepliesFor(String typed) {
  if (!typed.startsWith('/') || typed.contains(' ') || typed.contains('\n')) return const [];
  final q = typed.substring(1).toLowerCase();
  return [for (final r in AppState.instance.quickReplies) if ((r['k'] ?? '').toLowerCase().startsWith(q)) r];
}
