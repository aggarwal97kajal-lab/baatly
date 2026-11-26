import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/app_state.dart';
import '../../data/birthdays.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String fmtDob(String ymd) {
  final p = ymd.split('-');
  if (p.length != 3) return ymd;
  final m = (int.tryParse(p[1]) ?? 1).clamp(1, 12);
  return '${int.tryParse(p[2]) ?? 1} ${_months[m - 1]} ${p[0]}';
}

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Date picker for a date of birth ('YYYY-MM-DD').
Future<String?> pickDob(BuildContext context, {String? current}) async {
  final now = DateTime.now();
  DateTime init = DateTime(now.year - 20, now.month, now.day);
  if (current != null && current.isNotEmpty) init = DateTime.tryParse(current) ?? init;
  final d = await showDatePicker(
    context: context,
    initialDate: init,
    firstDate: DateTime(now.year - 110),
    lastDate: now,
    initialDatePickerMode: DatePickerMode.year,
    helpText: 'Date of birth',
  );
  return d == null ? null : _ymd(d);
}

String shareLabel(int v) => switch (v) { 0 => 'Everyone', 3 => 'Nobody', _ => 'My contacts' };

/// Tappable "Date of birth" field (used in profile setup and the required screen).
class DobField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const DobField({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Date of birth', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: bc.muted)),
      const SizedBox(height: 6),
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final v = await pickDob(context, current: value);
          if (v != null) onChanged(v);
        },
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(Icons.cake_outlined, color: value.isEmpty ? bc.muted : context.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value.isEmpty ? 'Select your date of birth' : fmtDob(value),
                  style: TextStyle(fontSize: 16, color: value.isEmpty ? bc.muted : bc.text)),
            ),
            Icon(Icons.expand_more_rounded, color: bc.muted),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Text('Required. Only the day and month are shown, to your contacts, so they can wish you.',
          style: TextStyle(fontSize: 12.5, color: bc.muted, height: 1.35)),
      const SizedBox(height: 16),
    ]);
  }
}

/// Shown once to accounts made before date of birth was required. Can't be skipped.
class DobRequiredScreen extends StatefulWidget {
  const DobRequiredScreen({super.key});
  @override
  State<DobRequiredScreen> createState() => _DobRequiredScreenState();
}

class _DobRequiredScreenState extends State<DobRequiredScreen> {
  String _dob = '';
  bool _saving = false;
  String? _err;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      await Birthdays.instance.saveMine(_dob);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _err = e.message);
    } catch (_) {
      setState(() => _err = "Couldn't save. Check your connection.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: bc.bg,
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 48, 24, 24), children: [
            Icon(Icons.cake_rounded, size: 64, color: context.primary),
            const SizedBox(height: 16),
            Text('Add your date of birth', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: bc.text)),
            const SizedBox(height: 8),
            Text('BAATLY reminds your contacts on your birthday so they can wish you. Your year of birth is never shown.',
                textAlign: TextAlign.center, style: TextStyle(color: bc.muted, height: 1.4)),
            const SizedBox(height: 28),
            DobField(value: _dob, onChanged: (v) => setState(() => _dob = v)),
            if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_err!, style: const TextStyle(color: Color(0xFFB3261E)))),
            FilledButton(
              onPressed: _dob.isEmpty || _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Continue'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Add / change / remove a birthday I keep for someone (only on this phone).
Future<void> editManualBirthday(BuildContext context, String id, String name) async {
  final s = AppState.instance;
  final now = DateTime.now();
  final cur = s.manualBirthdays[id] ?? s.knownBirthdays[id];
  DateTime init = DateTime(2000, now.month, now.day);
  if (cur != null) {
    final p = cur.split('-');
    init = DateTime(2000, int.tryParse(p[0]) ?? 1, int.tryParse(p[1]) ?? 1);
  }
  final d = await showDatePicker(
    context: context,
    initialDate: init,
    firstDate: DateTime(2000, 1, 1),
    lastDate: DateTime(2000, 12, 31),
    helpText: "$name's birthday",
  );
  if (d == null) return;
  final v = '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  s.toggle(() => s.manualBirthdays[id] = v);
  Birthdays.instance.changed();
}

/// Settings › Chats › Birthdays.
class BirthdaysScreen extends StatelessWidget {
  const BirthdaysScreen({super.key});

  Future<void> _addFor(BuildContext context) async {
    final chats = AppState.instance.chats.where((c) => !c.isGroup && c.peerId != null && !c.isNotes).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final Chat? pick = await showModalBottomSheet<Chat>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sh) => SizedBox(
        height: MediaQuery.of(sh).size.height * 0.7,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('Add birthday for', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          ),
          Expanded(
            child: ListView(children: [
              for (final c in chats)
                ListTile(
                  leading: Avatar(initials: c.initials, colorIndex: c.colorIndex, photo: c.photo, size: 40),
                  title: Text(c.name),
                  onTap: () => Navigator.pop(sh, c),
                ),
            ]),
          ),
        ]),
      ),
    );
    if (pick == null || !context.mounted) return;
    await editManualBirthday(context, pick.peerId!, pick.name);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final list = Birthdays.instance.upcoming();
        return Scaffold(
          appBar: AppBar(title: const Text('Birthdays'), actions: [
            IconButton(tooltip: 'Add birthday', icon: const Icon(Icons.add_rounded), onPressed: () => _addFor(context)),
          ]),
          body: ListView(children: [
            SwitchListTile(
              title: const Text('Birthday reminders'),
              subtitle: const Text('A notification at 12:00 am on their birthday'),
              value: s.birthdayReminders,
              onChanged: (v) {
                s.toggle(() => s.birthdayReminders = v);
                Birthdays.instance.changed();
              },
            ),
            ListTile(
              title: const Text('My date of birth'),
              subtitle: Text(s.myDob.isEmpty ? 'Not set' : fmtDob(s.myDob)),
              onTap: () async {
                final v = await pickDob(context, current: s.myDob);
                if (v == null) return;
                try {
                  await Birthdays.instance.saveMine(v);
                } on ApiException catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
            ),
            ListTile(
              title: const Text('Who can see my birthday'),
              subtitle: Text('${shareLabel(s.birthdayShare)} · day and month only'),
              onTap: () async {
                final v = await showModalBottomSheet<int>(
                  context: context,
                  showDragHandle: true,
                  builder: (sh) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final o in const [0, 1, 3])
                        ListTile(
                          leading: Icon(o == s.birthdayShare ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: sh.primary),
                          title: Text(shareLabel(o)),
                          onTap: () => Navigator.pop(sh, o),
                        ),
                    ]),
                  ),
                );
                if (v == null || s.myDob.isEmpty) return;
                try {
                  await Birthdays.instance.saveMine(s.myDob, share: v);
                } on ApiException catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('Upcoming', style: TextStyle(color: context.primary, fontWeight: FontWeight.w700)),
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No birthdays yet. They show up when your contacts share theirs, from your phone contacts, or when you add one with +.',
                    style: TextStyle(color: bc.muted, height: 1.4)),
              ),
            for (final e in list)
              ListTile(
                title: Text(e.name),
                subtitle: Text('${Birthdays.fmt('${e.next.month.toString().padLeft(2, '0')}-${e.next.day.toString().padLeft(2, '0')}')}${e.manual ? ' · added by you' : ''}'),
                trailing: Text(
                  e.today ? 'Today 🎂' : (() {
                    final n = DateTime.now();
                    final days = e.next.difference(DateTime(n.year, n.month, n.day)).inDays;
                    return days == 1 ? 'Tomorrow' : 'In $days days';
                  })(),
                  style: TextStyle(color: e.today ? context.primary : bc.muted, fontWeight: e.today ? FontWeight.w700 : FontWeight.w400),
                ),
                onTap: () async {
                  final chat = await Messenger.instance.chatForUser(e.id);
                  if (chat == null || !context.mounted) return;
                  AppState.instance.openChat(chat);
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
                },
                onLongPress: e.manual
                    ? () => s.toggle(() {
                          s.manualBirthdays.remove(e.id);
                          Birthdays.instance.changed();
                        })
                    : null,
              ),
          ]),
        );
      },
    );
  }
}

/// Card on the chat list on someone's birthday.
class BirthdayTodayCard extends StatelessWidget {
  const BirthdayTodayCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final n = DateTime.now();
    final day = _ymd(DateTime(n.year, n.month, n.day));
    final list = Birthdays.instance.today().where((e) => !s.birthdayCardsHidden.contains('$day:${e.id}')).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    final bc = context.bc;
    final e = list.first;
    final more = list.length - 1;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(Icons.cake_rounded, color: context.primary, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("${e.name}'s birthday is today", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: bc.text)),
            if (more > 0) Text('+ $more more', style: TextStyle(fontSize: 12.5, color: bc.muted)),
          ]),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 36), padding: const EdgeInsets.symmetric(horizontal: 14)),
          onPressed: () async {
            final chat = await Messenger.instance.chatForUser(e.id);
            if (chat == null || !context.mounted) return;
            AppState.instance.openChat(chat);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
          },
          child: const Text('Wish'),
        ),
        IconButton(
          icon: Icon(Icons.close_rounded, color: bc.muted, size: 20),
          onPressed: () => s.toggle(() {
            s.birthdayCardsHidden.removeWhere((k) => !k.startsWith(day));
            s.birthdayCardsHidden.add('$day:${e.id}');
          }),
        ),
      ]),
    );
  }
}
