import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';

/// Verify encryption: both people should see the same 60 digits.
class SafetyNumberScreen extends StatelessWidget {
  final Chat chat;
  const SafetyNumberScreen({super.key, required this.chat});
  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify security code')),
      body: FutureBuilder<String?>(
        future: Messenger.instance.safetyNumber(chat.peerId!),
        builder: (context, snap) {
          final n = snap.data;
          return ListView(padding: const EdgeInsets.all(24), children: [
            Icon(Icons.verified_user_outlined, size: 64, color: context.primary),
            const SizedBox(height: 16),
            if (snap.connectionState != ConnectionState.done)
              const Center(child: CircularProgressIndicator())
            else if (n == null)
              Text('Send ${chat.name} a message first to see the security code.', textAlign: TextAlign.center, style: TextStyle(color: bc.muted))
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: bc.surface, borderRadius: BorderRadius.circular(18)),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 18,
                  runSpacing: 12,
                  children: [
                    for (final g in n.split(' '))
                      Text(g, style: TextStyle(fontSize: 22, fontFamily: 'monospace', letterSpacing: 2, fontWeight: FontWeight.w600, color: bc.text)),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Text(
              "To verify that messages and calls with ${chat.name} are end-to-end encrypted, compare this number with the one on their phone "
              "(BAATLY → their chat with you → Encryption). If the numbers match, nobody is in between.",
              textAlign: TextAlign.center,
              style: TextStyle(color: bc.muted, height: 1.5),
            ),
          ]);
        },
      ),
    );
  }
}

Future<void> confirmBlock(BuildContext context, Chat chat) async {
  final ms = Messenger.instance;
  final isBlocked = ms.isBlocked(chat.peerId);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(isBlocked ? 'Unblock ${chat.name}?' : 'Block ${chat.name}?'),
      content: Text(isBlocked
          ? 'They will be able to message and call you again.'
          : "Blocked contacts can't call you or send you messages, and won't see your last seen, online or status updates."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(d, true), child: Text(isBlocked ? 'Unblock' : 'Block', style: const TextStyle(color: Color(0xFFB3261E)))),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ms.setBlocked(chat.peerId!, !isBlocked);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isBlocked ? '${chat.name} unblocked' : '${chat.name} blocked')));
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Future<void> showReportDialog(BuildContext context, Chat chat) async {
  var include = true;
  var block = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setD) => AlertDialog(
        title: Text('Report ${chat.name}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("The last 5 messages from this contact will be sent to BAATLY. They won't be told."),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: include,
            onChanged: (v) => setD(() => include = v ?? true),
            title: const Text('Include last 5 messages'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: block,
            onChanged: (v) => setD(() => block = v ?? true),
            title: const Text('Block contact'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Report', style: TextStyle(color: Color(0xFFB3261E)))),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await Messenger.instance.report(chat, includeMessages: include, alsoBlock: block);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report sent. Thank you.')));
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}
