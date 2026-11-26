import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../theme/app_theme.dart';

String _hm(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'am' : 'pm'}';
}

String busySummary() {
  final s = AppState.instance;
  if (!s.busyOn) return 'Off';
  return s.busySchedule ? 'Every day ${_hm(s.busyFrom)} – ${_hm(s.busyTo)}' : 'On until you turn it off';
}

/// Settings › Chats › Busy mode: auto-reply while you're busy.
class BusyModeScreen extends StatefulWidget {
  const BusyModeScreen({super.key});
  @override
  State<BusyModeScreen> createState() => _BusyModeScreenState();
}

class _BusyModeScreenState extends State<BusyModeScreen> {
  late final _text = TextEditingController(text: AppState.instance.busyText);

  @override
  void dispose() {
    final s = AppState.instance;
    final t = _text.text.trim();
    if (t.isNotEmpty && t != s.busyText) s.toggle(() => s.busyText = t);
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(bool from) async {
    final s = AppState.instance;
    final cur = from ? s.busyFrom : s.busyTo;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60));
    if (t == null) return;
    s.toggle(() => from ? s.busyFrom = t.hour * 60 + t.minute : s.busyTo = t.hour * 60 + t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Busy mode')),
        body: ListView(children: [
          SwitchListTile(
            title: const Text('Busy mode'),
            subtitle: const Text('Reply automatically when someone messages you'),
            value: s.busyOn,
            onChanged: (v) => s.toggle(() => s.busyOn = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Message', style: TextStyle(color: context.primary, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _text,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('When', style: TextStyle(color: context.primary, fontWeight: FontWeight.w700)),
          ),
          RadioListTile<bool>(
            title: const Text('Until I turn it off'),
            value: false,
            groupValue: s.busySchedule,
            onChanged: (v) => s.toggle(() => s.busySchedule = false),
          ),
          RadioListTile<bool>(
            title: const Text('Every day at set times'),
            value: true,
            groupValue: s.busySchedule,
            onChanged: (v) => s.toggle(() => s.busySchedule = true),
          ),
          if (s.busySchedule)
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
              child: Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => _pick(true), child: Text('From ${_hm(s.busyFrom)}'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton(onPressed: () => _pick(false), child: Text('To ${_hm(s.busyTo)}'))),
              ]),
            ),
          const Divider(),
          SwitchListTile(
            title: const Text('Also reply in groups'),
            subtitle: const Text('Once per group'),
            value: s.busyGroups,
            onChanged: (v) => s.toggle(() => s.busyGroups = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              'Each person gets the reply at most once every 3 hours. Your phone sends it, so it goes out when your phone has internet. Messages stay end-to-end encrypted.',
              style: TextStyle(color: bc.muted, height: 1.4),
            ),
          ),
        ]),
      ),
    );
  }
}
