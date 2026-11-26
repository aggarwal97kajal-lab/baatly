import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';

String _me() => Messenger.instance.myId ?? 'me';
String _who(String id) => id == _me() ? 'You' : Messenger.instance.nameFor(id);

/// ₹ with Indian grouping (₹1,23,456 or ₹1,234.50). [paise] is the amount × 100.
String rupees(int paise) {
  final neg = paise < 0;
  final p = paise.abs();
  final r = p ~/ 100;
  final ps = p % 100;
  final s = r.toString();
  String g;
  if (s.length <= 3) {
    g = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    g = '${parts.join(',')},$last3';
  }
  return '${neg ? '-' : ''}₹$g${ps == 0 ? '' : '.${ps.toString().padLeft(2, '0')}'}';
}

// =================================================================== checklist

/// 📎 › Checklist: title + first items.
class ChecklistCreateScreen extends StatefulWidget {
  const ChecklistCreateScreen({super.key});
  @override
  State<ChecklistCreateScreen> createState() => _ChecklistCreateScreenState();
}

class _ChecklistCreateScreenState extends State<ChecklistCreateScreen> {
  final _title = TextEditingController();
  final _items = [TextEditingController()];

  bool get _ok => _title.text.trim().isNotEmpty && _items.any((c) => c.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New checklist')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _ok ? context.primary : Colors.grey,
        foregroundColor: Colors.white,
        onPressed: !_ok
            ? null
            : () => Navigator.pop(context, {
                  'type': 'checklist',
                  'title': _title.text.trim(),
                  'items': [
                    for (final c in _items)
                      if (c.text.trim().isNotEmpty) {'id': Messenger.instance.newItemId(), 't': c.text.trim(), 'by': _me()}
                  ],
                }),
        child: const Icon(Icons.send_rounded),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _title,
          maxLength: 80,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Title', hintText: 'Ghar ka saaman'),
        ),
        const SizedBox(height: 6),
        const Text('Items', style: TextStyle(fontWeight: FontWeight.w700)),
        for (var i = 0; i < _items.length; i++)
          TextField(
            controller: _items[i],
            maxLength: 200,
            decoration: InputDecoration(
              hintText: '+ Add item',
              counterText: '',
              prefixIcon: const Icon(Icons.check_box_outline_blank_rounded),
              suffixIcon: _items.length > 1 ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _items.removeAt(i))) : null,
            ),
            onChanged: (_) {
              setState(() {});
              if (i == _items.length - 1 && _items[i].text.isNotEmpty && _items.length < 50) {
                setState(() => _items.add(TextEditingController()));
              }
            },
          ),
        const SizedBox(height: 12),
        Text('Everyone in this chat can tick and add items.', style: TextStyle(color: context.bc.muted)),
        const SizedBox(height: 80),
      ]),
    );
  }
}

class ChecklistContent extends StatelessWidget {
  final Chat chat;
  final Message m;
  final Color fg;
  final Color accent;
  const ChecklistContent({super.key, required this.chat, required this.m, required this.fg, required this.accent});

  Future<void> _add(BuildContext context) async {
    final c = TextEditingController();
    final t = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Add item'),
        content: TextField(controller: c, autofocus: true, maxLength: 200, textCapitalization: TextCapitalization.sentences, onSubmitted: (v) => Navigator.pop(d, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Add')),
        ],
      ),
    );
    if (t == null || t.trim().isEmpty) return;
    Messenger.instance.checklistOp(chat, m, 'add', Messenger.instance.newItemId(), text: t.trim());
  }

  @override
  Widget build(BuildContext context) {
    final md = m.media ?? {};
    final items = [for (final x in (md['items'] as List? ?? [])) (x as Map).cast<String, dynamic>()];
    final done = items.where((x) => x['done'] != null).length;
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.68,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.checklist_rounded, size: 19, color: accent),
          const SizedBox(width: 6),
          Expanded(child: Text(md['title'] as String? ?? 'Checklist', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: fg))),
        ]),
        const SizedBox(height: 6),
        for (final it in items)
          InkWell(
            onTap: () => Messenger.instance.checklistOp(chat, m, it['done'] == null ? 'tick' : 'untick', it['id'] as String),
            onLongPress: () async {
              final rm = await showModalBottomSheet<bool>(
                context: context,
                builder: (sh) => SafeArea(
                  child: ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Remove item'), onTap: () => Navigator.pop(sh, true)),
                ),
              );
              if (rm == true) Messenger.instance.checklistOp(chat, m, 'rm', it['id'] as String);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(it['done'] != null ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 21, color: it['done'] != null ? accent : fg.withOpacity(0.7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(it['t'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 14.5,
                        color: it['done'] != null ? fg.withOpacity(0.6) : fg,
                        decoration: it['done'] != null ? TextDecoration.lineThrough : null,
                      )),
                ),
                if (it['done'] != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 2),
                    child: Text(_who(it['done'] as String), style: TextStyle(fontSize: 11, color: fg.withOpacity(0.65))),
                  ),
              ]),
            ),
          ),
        Divider(color: fg.withOpacity(0.15), height: 14),
        Row(children: [
          InkWell(
            onTap: () => _add(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('+ Add item', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13.5)),
            ),
          ),
          const Spacer(),
          Text('$done of ${items.length} done', style: TextStyle(fontSize: 11.5, color: fg.withOpacity(0.7))),
        ]),
      ]),
    );
  }
}

// =================================================================== hisaab (shared expenses)

List<String> ledgerPeople(Chat chat) {
  final me = _me();
  final out = <String>{me};
  if (chat.isGroup) {
    out.addAll(chat.members);
  } else if (chat.peerId != null) {
    out.add(chat.peerId!);
  }
  out.removeWhere((x) => x.isEmpty);
  return out.toList();
}

List<Map<String, dynamic>> _expenses(Message m) => [for (final x in (m.media?['exp'] as List? ?? [])) (x as Map).cast<String, dynamic>()];

/// Net per person: + gets money back, − owes (paise).
Map<String, int> ledgerNet(Message m) {
  final net = <String, int>{};
  for (final e in _expenses(m)) {
    final a = (e['a'] as num).toInt();
    final split = [for (final x in (e['s'] as List)) x.toString()];
    final p = e['p'] as String;
    net[p] = (net[p] ?? 0) + a;
    final each = a ~/ split.length;
    var rem = a - each * split.length;
    for (final u in split) {
      final share = each + (rem > 0 ? 1 : 0);
      if (rem > 0) rem--;
      net[u] = (net[u] ?? 0) - share;
    }
  }
  return net;
}

/// Fewest payments that settle everything: (from, to, paise).
List<(String, String, int)> ledgerSettle(Message m) {
  final net = ledgerNet(m);
  final cred = [for (final e in net.entries) if (e.value > 0) [e.key, e.value]]..sort((a, b) => (b[1] as int).compareTo(a[1] as int));
  final debt = [for (final e in net.entries) if (e.value < 0) [e.key, -e.value]]..sort((a, b) => (b[1] as int).compareTo(a[1] as int));
  final out = <(String, String, int)>[];
  var i = 0, j = 0;
  while (i < debt.length && j < cred.length) {
    final x = (debt[i][1] as int) < (cred[j][1] as int) ? debt[i][1] as int : cred[j][1] as int;
    if (x > 0) out.add((debt[i][0] as String, cred[j][0] as String, x));
    debt[i][1] = (debt[i][1] as int) - x;
    cred[j][1] = (cred[j][1] as int) - x;
    if ((debt[i][1] as int) == 0) i++;
    if ((cred[j][1] as int) == 0) j++;
  }
  return out;
}

int ledgerTotal(Message m) => _expenses(m).where((e) => e['st'] != true).fold(0, (a, e) => a + (e['a'] as num).toInt());

class LedgerCreateScreen extends StatefulWidget {
  const LedgerCreateScreen({super.key});
  @override
  State<LedgerCreateScreen> createState() => _LedgerCreateScreenState();
}

class _LedgerCreateScreenState extends State<LedgerCreateScreen> {
  final _t = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final ok = _t.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('New hisaab')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: ok ? context.primary : Colors.grey,
        foregroundColor: Colors.white,
        onPressed: ok ? () => Navigator.pop(context, {'type': 'ledger', 'title': _t.text.trim(), 'exp': <dynamic>[]}) : null,
        child: const Icon(Icons.send_rounded),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _t,
          autofocus: true,
          maxLength: 60,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'What is it for?', hintText: 'Goa trip'),
        ),
        const SizedBox(height: 8),
        Text('Everyone in this chat can add expenses. BAATLY works out who owes whom. No money moves through the app; it only keeps the hisaab.',
            style: TextStyle(color: context.bc.muted, height: 1.4)),
      ]),
    );
  }
}

class LedgerContent extends StatelessWidget {
  final Chat chat;
  final Message m;
  final Color fg;
  final Color accent;
  const LedgerContent({super.key, required this.chat, required this.m, required this.fg, required this.accent});

  @override
  Widget build(BuildContext context) {
    final md = m.media ?? {};
    final total = ledgerTotal(m);
    final mine = ledgerNet(m)[_me()] ?? 0;
    final n = _expenses(m).where((e) => e['st'] != true).length;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LedgerScreen(chat: chat, msgId: m.id))),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.62,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Icons.currency_rupee_rounded, size: 18, color: accent),
            const SizedBox(width: 4),
            Expanded(child: Text(md['title'] as String? ?? 'Hisaab', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: fg))),
          ]),
          const SizedBox(height: 6),
          Text(rupees(total), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: fg)),
          Text('$n expense${n == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: fg.withOpacity(0.7))),
          Divider(color: fg.withOpacity(0.15), height: 16),
          Text(
            mine == 0 ? 'You are settled up' : (mine > 0 ? 'You get back ${rupees(mine)}' : 'You owe ${rupees(-mine)}'),
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg),
          ),
          const SizedBox(height: 6),
          Text('Open hisaab', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13.5)),
        ]),
      ),
    );
  }
}

class LedgerScreen extends StatelessWidget {
  final Chat chat;
  final String msgId;
  const LedgerScreen({super.key, required this.chat, required this.msgId});

  Message? get _m {
    for (final x in chat.messages) {
      if (x.id == msgId) return x;
    }
    return null;
  }

  Future<void> _addExpense(BuildContext context, Message m) async {
    final people = ledgerPeople(chat);
    final d = TextEditingController();
    final a = TextEditingController();
    var payer = _me();
    final split = {...people};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sh) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(sh).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (sh, set) {
          final amt = ((double.tryParse(a.text.trim()) ?? 0) * 100).round();
          final valid = d.text.trim().isNotEmpty && amt > 0 && split.isNotEmpty;
          return SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Add expense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(controller: d, maxLength: 60, onChanged: (_) => set(() {}), decoration: const InputDecoration(labelText: 'For what', hintText: 'Dinner')),
              TextField(
                controller: a,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => set(() {}),
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
              ),
              const SizedBox(height: 14),
              const Text('Paid by', style: TextStyle(fontWeight: FontWeight.w700)),
              Wrap(spacing: 8, children: [
                for (final p in people) ChoiceChip(label: Text(_who(p)), selected: payer == p, onSelected: (_) => set(() => payer = p)),
              ]),
              const SizedBox(height: 10),
              const Text('Split equally between', style: TextStyle(fontWeight: FontWeight.w700)),
              Wrap(spacing: 8, children: [
                for (final p in people)
                  FilterChip(
                    label: Text(_who(p)),
                    selected: split.contains(p),
                    onSelected: (v) => set(() => v ? split.add(p) : split.remove(p)),
                  ),
              ]),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(sh, true) : null,
                child: Text(valid ? 'Save · ${rupees(amt ~/ split.length)} each' : 'Save'),
              ),
            ]),
          );
        }),
      ),
    );
    if (ok != true) return;
    final amt = ((double.tryParse(a.text.trim()) ?? 0) * 100).round();
    Messenger.instance.ledgerOp(chat, m, 'add', {
      'id': Messenger.instance.newItemId(),
      'd': d.text.trim(),
      'a': amt,
      'p': payer,
      's': split.toList(),
      'at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final m = _m;
        final bc = context.bc;
        if (m == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('This hisaab was deleted')));
        final exp = _expenses(m).reversed.toList();
        final settle = ledgerSettle(m);
        final total = ledgerTotal(m);
        final me = _me();
        return Scaffold(
          appBar: AppBar(title: Text(m.media?['title'] as String? ?? 'Hisaab')),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: context.primary,
            foregroundColor: Colors.white,
            onPressed: () => _addExpense(context, m),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add expense'),
          ),
          body: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
            const SizedBox(height: 18),
            Text('Total spent', textAlign: TextAlign.center, style: TextStyle(color: bc.muted)),
            Text(rupees(total), textAlign: TextAlign.center, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: bc.text)),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text('Who pays whom', style: TextStyle(color: context.primary, fontWeight: FontWeight.w700)),
            ),
            if (settle.isEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Text('Everyone is settled up 🎉', style: TextStyle(color: bc.muted))),
            for (final s in settle)
              ListTile(
                title: Text('${_who(s.$1)} → ${_who(s.$2)}', style: TextStyle(color: bc.text)),
                subtitle: Text(rupees(s.$3), style: TextStyle(fontWeight: FontWeight.w700, color: s.$2 == me ? const Color(0xFF3EC28F) : bc.text)),
                trailing: (s.$1 == me || s.$2 == me)
                    ? TextButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (d) => AlertDialog(
                              title: const Text('Mark as paid?'),
                              content: Text('${_who(s.$1)} paid ${_who(s.$2)} ${rupees(s.$3)} outside BAATLY.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                                TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Mark paid')),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          Messenger.instance.ledgerOp(chat, m, 'add', {
                            'id': Messenger.instance.newItemId(),
                            'd': 'Paid back',
                            'a': s.$3,
                            'p': s.$1,
                            's': [s.$2],
                            'st': true,
                            'at': DateTime.now().millisecondsSinceEpoch,
                          });
                        },
                        child: const Text('Mark paid'),
                      )
                    : null,
              ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Expenses', style: TextStyle(color: context.primary, fontWeight: FontWeight.w700)),
            ),
            if (exp.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text('No expenses yet. Tap "Add expense".', style: TextStyle(color: bc.muted))),
            for (final e in exp)
              ListTile(
                leading: Icon(e['st'] == true ? Icons.handshake_outlined : Icons.receipt_long_rounded, color: bc.muted),
                title: Text(e['st'] == true ? '${_who(e['p'] as String)} paid ${_who((e['s'] as List).first.toString())}' : (e['d'] as String? ?? ''),
                    style: TextStyle(color: bc.text)),
                subtitle: Text(
                    e['st'] == true
                        ? 'Settled'
                        : '${_who(e['p'] as String)} paid · split ${(e['s'] as List).length} way${(e['s'] as List).length == 1 ? '' : 's'}',
                    style: TextStyle(color: bc.muted)),
                trailing: Text(rupees((e['a'] as num).toInt()), style: TextStyle(fontWeight: FontWeight.w700, color: bc.text)),
                onLongPress: (e['by'] == me || e['p'] == me)
                    ? () async {
                        final del = await showModalBottomSheet<bool>(
                          context: context,
                          builder: (sh) => SafeArea(
                            child: ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Delete expense'), onTap: () => Navigator.pop(sh, true)),
                          ),
                        );
                        if (del == true) Messenger.instance.ledgerOp(chat, m, 'del', {'id': e['id']});
                      }
                    : null,
              ),
          ]),
        );
      },
    );
  }
}
