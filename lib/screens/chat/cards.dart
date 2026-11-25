import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../data/contacts.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../widgets/photo_viewer.dart';
import 'chat_screen.dart';

String _two(int n) => n.toString().padLeft(2, '0');
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String fmtWhen(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${t.day} ${_months[t.month - 1]} ${t.year}, $h:${_two(t.minute)} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// Poll with live vote counts; tap an option to vote.
class PollContent extends StatelessWidget {
  final Chat chat;
  final Message m;
  final Color fg;
  final Color accent;
  const PollContent({super.key, required this.chat, required this.m, required this.fg, required this.accent});

  @override
  Widget build(BuildContext context) {
    final md = m.media ?? {};
    final opts = [for (final o in (md['opts'] as List? ?? [])) o.toString()];
    final multi = md['multi'] == true;
    final votes = ((md['votes'] as Map?) ?? {}).cast<String, dynamic>();
    final me = Messenger.instance.myId ?? 'me';
    final mine = {for (final x in (votes[me] as List? ?? [])) (x as num).toInt()};
    final counts = List<int>.filled(opts.length, 0);
    for (final v in votes.values) {
      for (final x in (v as List? ?? [])) {
        final i = (x as num).toInt();
        if (i >= 0 && i < counts.length) counts[i]++;
      }
    }
    final voters = votes.values.where((v) => (v as List).isNotEmpty).length;
    final maxC = counts.fold<int>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.66,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(md['q'] as String? ?? '', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: fg)),
        const SizedBox(height: 2),
        Text(multi ? 'Select one or more' : 'Select one', style: TextStyle(fontSize: 11.5, color: fg.withOpacity(0.7))),
        const SizedBox(height: 8),
        for (var i = 0; i < opts.length; i++)
          InkWell(
            onTap: () {
              final next = {...mine};
              if (multi) {
                next.contains(i) ? next.remove(i) : next.add(i);
              } else {
                next.contains(i) ? next.clear() : (next..clear()..add(i));
              }
              Messenger.instance.vote(chat, m, next.toList()..sort());
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Icon(mine.contains(i) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 22, color: mine.contains(i) ? accent : fg.withOpacity(0.6)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(opts[i], style: TextStyle(fontSize: 14, color: fg))),
                      Text('${counts[i]}', style: TextStyle(fontSize: 12.5, color: fg.withOpacity(0.8))),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: maxC == 0 ? 0 : counts[i] / maxC,
                        minHeight: 5,
                        color: accent,
                        backgroundColor: fg.withOpacity(0.15),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 4),
        Text('$voters ${voters == 1 ? 'vote' : 'votes'}', style: TextStyle(fontSize: 11.5, color: fg.withOpacity(0.7))),
      ]),
    );
  }
}

/// Shared contact card: message them on BAATLY or invite.
class ContactContent extends StatelessWidget {
  final Message m;
  final Color fg;
  const ContactContent({super.key, required this.m, required this.fg});
  @override
  Widget build(BuildContext context) {
    final md = m.media ?? {};
    final name = md['name'] as String? ?? 'Contact';
    final phone = md['phone'] as String? ?? '';
    final uid = md['uid'] as String?;
    return Container(
      width: MediaQuery.of(context).size.width * 0.62,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: fg.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(radius: 20, backgroundColor: fg.withOpacity(0.2), child: Icon(Icons.person_rounded, color: fg)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
              Text(ContactBook.pretty(phone), style: TextStyle(fontSize: 12, color: fg.withOpacity(0.75))),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () async {
            if (uid != null && uid != Messenger.instance.myId && Api.instance.loggedIn) {
              final chat = Messenger.instance.chatWithUser(uid, name, phone, null);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
            } else {
              final text = Uri.encodeComponent("Let's chat on BAATLY! Download: https://baatly-api.pitaragames.workers.dev/get");
              await launchUrl(Uri.parse('sms:$phone?body=$text'), mode: LaunchMode.externalApplication);
            }
          },
          child: Text(uid != null ? 'Message' : 'Invite to BAATLY', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// Event card with "Add to calendar".
class EventContent extends StatelessWidget {
  final Message m;
  final Color fg;
  const EventContent({super.key, required this.m, required this.fg});
  @override
  Widget build(BuildContext context) {
    final md = m.media ?? {};
    final title = md['title'] as String? ?? 'Event';
    final at = DateTime.fromMillisecondsSinceEpoch((md['at'] as int?) ?? 0);
    final place = md['place'] as String? ?? '';
    return Container(
      width: MediaQuery.of(context).size.width * 0.64,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: fg.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(radius: 18, backgroundColor: Color(0xFFD9467A), child: Icon(Icons.event_rounded, color: Colors.white, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: fg))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.schedule_rounded, size: 16, color: fg.withOpacity(0.75)),
          const SizedBox(width: 6),
          Text(fmtWhen(at), style: TextStyle(fontSize: 13, color: fg)),
        ]),
        if (place.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.place_outlined, size: 16, color: fg.withOpacity(0.75)),
            const SizedBox(width: 6),
            Expanded(child: Text(place, style: TextStyle(fontSize: 13, color: fg))),
          ]),
        ],
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () {
            String f(DateTime d) {
              final u = d.toUtc();
              return '${u.year}${_two(u.month)}${_two(u.day)}T${_two(u.hour)}${_two(u.minute)}00Z';
            }
            final end = at.add(const Duration(hours: 1));
            final url = 'https://calendar.google.com/calendar/render?action=TEMPLATE'
                '&text=${Uri.encodeComponent(title)}&dates=${f(at)}/${f(end)}'
                '${place.isEmpty ? '' : '&location=${Uri.encodeComponent(place)}'}';
            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          },
          icon: Icon(Icons.calendar_month_rounded, color: fg),
          label: Text('Add to calendar', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// View-once photo: opens one time, then it's gone.
class ViewOnceContent extends StatelessWidget {
  final Chat chat;
  final Message m;
  final Color fg;
  const ViewOnceContent({super.key, required this.chat, required this.m, required this.fg});
  @override
  Widget build(BuildContext context) {
    final label = m.fromMe ? (m.opened ? 'Opened' : 'Photo') : (m.opened ? 'Opened' : (m.busy ? 'Loading…' : 'Photo'));
    return InkWell(
      onTap: m.fromMe || m.opened
          ? null
          : () async {
              final p = m.mediaPath ?? await Messenger.instance.downloadMedia(m);
              if (p == null || !context.mounted) return;
              await Navigator.of(context).push(PageRouteBuilder<void>(
                opaque: false,
                barrierColor: Colors.black,
                pageBuilder: (_, __, ___) => PhotoViewerScreen(path: p, title: 'View once'),
              ));
              await Messenger.instance.markOpened(chat, m);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: fg, width: 1.6, style: m.opened ? BorderStyle.solid : BorderStyle.solid)),
            child: Text('1', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fg)),
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 15, color: fg.withOpacity(m.opened ? 0.7 : 1), fontStyle: m.opened ? FontStyle.italic : FontStyle.normal)),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ create screens

/// Create a poll: question + 2–12 options, single or multiple choice.
class PollCreateScreen extends StatefulWidget {
  const PollCreateScreen({super.key});
  @override
  State<PollCreateScreen> createState() => _PollCreateScreenState();
}

class _PollCreateScreenState extends State<PollCreateScreen> {
  final _q = TextEditingController();
  final _opts = [TextEditingController(), TextEditingController()];
  bool _multi = false;

  bool get _ok => _q.text.trim().isNotEmpty && _opts.where((c) => c.text.trim().isNotEmpty).length >= 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create poll')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _ok ? Theme.of(context).colorScheme.primary : Colors.grey,
        foregroundColor: Colors.white,
        onPressed: !_ok
            ? null
            : () => Navigator.pop(context, {
                  'type': 'poll',
                  'q': _q.text.trim(),
                  'opts': [for (final c in _opts) if (c.text.trim().isNotEmpty) c.text.trim()],
                  'multi': _multi,
                  'votes': <String, dynamic>{},
                }),
        child: const Icon(Icons.send_rounded),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _q, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Question'), maxLength: 255),
        const SizedBox(height: 8),
        const Text('Options', style: TextStyle(fontWeight: FontWeight.w700)),
        for (var i = 0; i < _opts.length; i++)
          TextField(
            controller: _opts[i],
            maxLength: 100,
            decoration: InputDecoration(hintText: '+ Add option', counterText: '', suffixIcon: _opts.length > 2 ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _opts.removeAt(i))) : null),
            onChanged: (_) {
              setState(() {});
              if (i == _opts.length - 1 && _opts[i].text.isNotEmpty && _opts.length < 12) {
                setState(() => _opts.add(TextEditingController()));
              }
            },
          ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow multiple answers'),
          value: _multi,
          onChanged: (v) => setState(() => _multi = v),
        ),
        const SizedBox(height: 80),
      ]),
    );
  }
}

/// Create an event: name, date, time, place.
class EventCreateScreen extends StatefulWidget {
  const EventCreateScreen({super.key});
  @override
  State<EventCreateScreen> createState() => _EventCreateScreenState();
}

class _EventCreateScreenState extends State<EventCreateScreen> {
  final _title = TextEditingController();
  final _place = TextEditingController();
  DateTime _at = DateTime.now().add(const Duration(hours: 1)).copyWith(minute: 0, second: 0, millisecond: 0, microsecond: 0);

  @override
  Widget build(BuildContext context) {
    final ok = _title.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Create event')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: ok ? Theme.of(context).colorScheme.primary : Colors.grey,
        foregroundColor: Colors.white,
        onPressed: !ok
            ? null
            : () => Navigator.pop(context, {
                  'type': 'event',
                  'title': _title.text.trim(),
                  'at': _at.millisecondsSinceEpoch,
                  'place': _place.text.trim(),
                }),
        child: const Icon(Icons.send_rounded),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _title, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Event name'), maxLength: 100),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today_rounded),
          title: Text(fmtWhen(_at)),
          subtitle: const Text('Tap to change date and time'),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _at, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 730)));
            if (d == null || !context.mounted) return;
            final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
            if (t == null) return;
            setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
          },
        ),
        TextField(controller: _place, decoration: const InputDecoration(labelText: 'Location (optional)', prefixIcon: Icon(Icons.place_outlined))),
      ]),
    );
  }
}

/// Pick a phone contact to share.
class ShareContactScreen extends StatefulWidget {
  const ShareContactScreen({super.key});
  @override
  State<ShareContactScreen> createState() => _ShareContactScreenState();
}

class _ShareContactScreenState extends State<ShareContactScreen> {
  List<Map<String, dynamic>>? _all;
  String _q = '';
  String? _err;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final r = await ContactBook.instance.load();
        if (!r.permission) {
          setState(() => _err = 'Allow contacts to share one.');
          return;
        }
        final list = <Map<String, dynamic>>[
          for (final c in r.onBaatly) {'name': c.name, 'phone': c.phone, 'uid': c.userId},
          for (final c in r.invite) {'name': c.name, 'phone': c.e164},
        ]..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
        if (mounted) setState(() => _all = list);
      } catch (e) {
        if (mounted) setState(() => _err = "Couldn't read contacts ($e)");
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final list = (_all ?? []).where((c) => _q.isEmpty || (c['name'] as String).toLowerCase().contains(_q.toLowerCase()) || (c['phone'] as String).contains(_q)).toList();
    return Scaffold(
      appBar: AppBar(title: TextField(autofocus: false, onChanged: (v) => setState(() => _q = v.trim()), decoration: const InputDecoration(hintText: 'Search contacts', border: InputBorder.none))),
      body: _err != null
          ? Center(child: Text(_err!))
          : _all == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final c = list[i];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                      title: Text(c['name'] as String),
                      subtitle: Text(ContactBook.pretty(c['phone'] as String) + (c['uid'] != null ? ' · on BAATLY' : '')),
                      onTap: () => Navigator.pop(context, {'type': 'contact', ...c}),
                    );
                  },
                ),
    );
  }
}
