import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/api.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

String _dayTime(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  final diff = d.difference(today).inDays;
  final day = switch (diff) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][t.weekday - 1],
  };
  final label = (diff.abs() <= 1 || (diff > 1 && diff < 7)) ? day : '${t.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][t.month - 1]}';
  return '$label, ${hhmm(t)}';
}

String dayTime(DateTime t) => _dayTime(t);

// ------------------------------------------------------------------ time picking
/// Quick choices + "Pick date & time". Returns null if cancelled.
Future<DateTime?> pickWhen(BuildContext context, {required String title, required List<(String, DateTime)> quick}) async {
  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (sh) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 8), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        for (final (label, at) in quick)
          ListTile(
            leading: const Icon(Icons.schedule_rounded),
            title: Text(label),
            subtitle: Text(_dayTime(at)),
            onTap: () => Navigator.pop(sh, at),
          ),
        ListTile(
          leading: Icon(Icons.edit_calendar_rounded, color: sh.primary),
          title: Text('Pick date & time', style: TextStyle(color: sh.primary, fontWeight: FontWeight.w600)),
          onTap: () => Navigator.pop(sh, 'pick'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (choice is DateTime) return choice;
  if (choice != 'pick' || !context.mounted) return null;
  final now = DateTime.now();
  final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), initialDate: now);
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
  if (t == null) return null;
  final at = DateTime(d.year, d.month, d.day, t.hour, t.minute);
  if (!at.isAfter(DateTime.now())) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a time in the future')));
    return null;
  }
  return at;
}

DateTime _at(int dayOffset, int hour, [int minute = 0]) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + dayOffset, hour, minute);
}

List<(String, DateTime)> _scheduleQuick() {
  final n = DateTime.now();
  final out = <(String, DateTime)>[];
  if (n.hour < 20) out.add(('Tonight', _at(0, 21)));
  out.add(('Tomorrow morning', _at(1, 9)));
  final toMonday = (DateTime.monday - n.weekday + 7) % 7;
  out.add(('Next Monday', _at(toMonday == 0 ? 7 : toMonday, 9)));
  return out;
}

// ------------------------------------------------------------------ schedule
/// Long-press on send: choose when the message goes.
Future<bool> scheduleFromComposer(BuildContext context, Chat chat, String text) async {
  if (text.trim().isEmpty || !chat.isReal) return false;
  final at = await pickWhen(context, title: 'Schedule message', quick: _scheduleQuick());
  if (at == null) return false;
  try {
    await Messenger.instance.scheduleText(chat, text.trim(), at);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Will be sent ${_dayTime(at)}')));
    return true;
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : "Couldn't schedule. Check your connection.")));
    return false;
  }
}

/// Tap on a scheduled message.
Future<void> scheduledOptions(BuildContext context, Chat chat, Message m) async {
  final v = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sh) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.send_rounded), title: const Text('Send now'), onTap: () => Navigator.pop(sh, 'now')),
        ListTile(leading: const Icon(Icons.schedule_rounded), title: const Text('Change time'), onTap: () => Navigator.pop(sh, 'time')),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE5484D)),
          title: const Text('Delete', style: TextStyle(color: Color(0xFFE5484D))),
          onTap: () => Navigator.pop(sh, 'del'),
        ),
      ]),
    ),
  );
  if (v == null || !context.mounted) return;
  try {
    if (v == 'now') await Messenger.instance.sendScheduledNow(chat, m);
    if (v == 'del') await Messenger.instance.cancelScheduled(chat, m);
    if (v == 'time') {
      final at = await pickWhen(context, title: 'Change time', quick: _scheduleQuick());
      if (at != null) await Messenger.instance.reschedule(chat, m, at);
    }
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't change it. Check your connection.")));
  }
}

class ScheduledScreen extends StatelessWidget {
  final Chat chat;
  const ScheduledScreen({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final list = Messenger.instance.scheduledIn(chat);
        return Scaffold(
          backgroundColor: bc.bg,
          appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Scheduled messages'),
            Text(chat.name, style: TextStyle(fontSize: 12.5, color: bc.muted, fontWeight: FontWeight.w400)),
          ])),
          body: list.isEmpty
              ? Center(child: Text('No scheduled messages', style: TextStyle(color: bc.muted)))
              : ListView(padding: const EdgeInsets.all(14), children: [
                  for (final m in list)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: bc.surface, borderRadius: BorderRadius.circular(16)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_dayTime(m.time), style: TextStyle(color: context.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(m.text, style: TextStyle(color: bc.text, fontSize: 15)),
                        const SizedBox(height: 6),
                        Row(children: [
                          TextButton(onPressed: () => Messenger.instance.sendScheduledNow(chat, m), child: const Text('Send now')),
                          TextButton(
                            onPressed: () async {
                              final at = await pickWhen(context, title: 'Change time', quick: _scheduleQuick());
                              if (at != null) await Messenger.instance.reschedule(chat, m, at);
                            },
                            child: const Text('Change time'),
                          ),
                          TextButton(
                            onPressed: () => Messenger.instance.cancelScheduled(chat, m),
                            child: const Text('Delete', style: TextStyle(color: Color(0xFFE5484D))),
                          ),
                        ]),
                      ]),
                    ),
                ]),
        );
      },
    );
  }
}

// ------------------------------------------------------------------ reminder
Future<void> remindMe(BuildContext context, Chat chat, Message m) async {
  final n = DateTime.now();
  final quick = <(String, DateTime)>[
    ('In 1 hour', n.add(const Duration(hours: 1))),
    if (n.hour < 17) ('This evening', _at(0, 18)),
    ('Tomorrow morning', _at(1, 9)),
  ];
  final at = await pickWhen(context, title: 'Remind me about this message', quick: quick);
  if (at == null) return;
  try {
    await Messenger.instance.setReminder(chat, m, at);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⏰ Reminder set for ${_dayTime(at)}')));
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't set the reminder. Check your connection.")));
  }
}

// ------------------------------------------------------------------ message info
class MessageInfoScreen extends StatelessWidget {
  final Chat chat;
  final Message m;
  final Widget bubble;
  const MessageInfoScreen({super.key, required this.chat, required this.m, required this.bubble});

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    String when(int? ms) => ms == null ? '—' : _dayTime(DateTime.fromMillisecondsSinceEpoch(ms));
    Widget row(IconData icon, Color c, String label, String sub) => ListTile(
          leading: Icon(icon, color: c),
          title: Text(label, style: TextStyle(color: bc.text)),
          subtitle: Text(sub, style: TextStyle(color: bc.muted)),
        );
    const blue = Color(0xFF4FA8FF);
    final children = <Widget>[
      Container(
        color: bc.bg,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 6),
        child: IgnorePointer(child: bubble),
      ),
      Divider(height: 1, color: bc.line),
    ];
    if (!chat.isRealGroup) {
      final read = m.receiptAt['r'] ?? (m.status == MsgStatus.read ? -1 : null);
      final del = m.receiptAt['d'] ?? (m.status.index >= MsgStatus.delivered.index ? -1 : null);
      children.addAll([
        row(Icons.done_all_rounded, blue, 'Read', read == -1 ? 'Read' : when(read)),
        row(Icons.done_all_rounded, bc.muted, 'Delivered', del == -1 ? 'Delivered' : when(del)),
        if (m.status == MsgStatus.sent || m.status == MsgStatus.sending) row(Icons.done_rounded, bc.muted, 'Sent', _dayTime(m.time)),
      ]);
    } else {
      final others = chat.members.where((u) => u != Messenger.instance.myId).toList();
      final readers = others.where(m.readBy.contains).toList()
        ..sort((a, b) => (m.receiptAt['r:$a'] ?? 0).compareTo(m.receiptAt['r:$b'] ?? 0));
      final delivered = others.where((u) => m.deliveredBy.contains(u) && !m.readBy.contains(u)).toList();
      final remaining = others.length - readers.length - delivered.length;
      Widget person(String u, int? at) => ListTile(
            leading: Avatar(initials: Messenger.initialsOf(Messenger.instance.nameFor(u)), colorIndex: u.length % 7, photo: Messenger.instance.photoOf(u), size: 40),
            title: Text(Messenger.instance.nameFor(u), style: TextStyle(color: bc.text)),
            subtitle: Text(when(at), style: TextStyle(color: bc.muted)),
          );
      Widget head(IconData i, Color c, String t, String right) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(children: [
              Icon(i, size: 20, color: c),
              const SizedBox(width: 10),
              Expanded(child: Text(t, style: TextStyle(color: bc.muted, fontSize: 13.5))),
              Text(right, style: TextStyle(color: bc.muted, fontSize: 13.5)),
            ]),
          );
      children.addAll([
        head(Icons.done_all_rounded, blue, 'Read by', '${readers.length} of ${others.length}'),
        if (readers.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Text('—', style: TextStyle(color: bc.muted))),
        for (final u in readers) person(u, m.receiptAt['r:$u']),
        head(Icons.done_all_rounded, bc.muted, 'Delivered to', ''),
        if (delivered.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), child: Text('—', style: TextStyle(color: bc.muted))),
        for (final u in delivered) person(u, m.receiptAt['d:$u']),
        if (remaining > 0) Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 10), child: Text('$remaining remaining', style: TextStyle(color: bc.muted))),
      ]);
    }
    return Scaffold(
      backgroundColor: bc.surface,
      appBar: AppBar(title: const Text('Message info')),
      body: ListView(children: children),
    );
  }
}
