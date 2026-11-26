import 'package:flutter/material.dart';

import '../../data/accounts.dart';
import '../../data/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

String _ini(String name) {
  final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

String _tail(String phone) {
  final p = phone.replaceAll(RegExp(r'\D'), '');
  return p.length >= 4 ? '••${p.substring(p.length - 4)}' : phone;
}

Future<void> _confirmAdd(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Add account'),
      content: const Text(
          'Log in with another number. This account stays logged in and you can switch back any time. Calls work on the open account only.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Continue')),
      ],
    ),
  );
  if (ok == true) await Accounts.instance.beginAdd();
}

/// Accounts list in Settings: the open one, the other one (tap to switch), Add account.
class AccountsSection extends StatelessWidget {
  const AccountsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    return ValueListenableBuilder<List<SavedAccount>>(
      valueListenable: Accounts.instance.others,
      builder: (context, others, _) => Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Avatar(initials: _ini(s.name.isEmpty ? 'You' : s.name), colorIndex: 2, size: 40, photo: s.myPhoto),
          title: Text(s.name.isEmpty ? 'You' : s.name),
          subtitle: Text('${_tail(s.phone)} · open now'),
          trailing: Icon(Icons.check_circle_rounded, color: context.primary),
        ),
        for (final a in others)
          ListTile(
            leading: Avatar(initials: _ini(a.name), colorIndex: 4, size: 40, photo: a.photo),
            title: Text(a.name),
            subtitle: Text(_tail(a.phone)),
            trailing: a.unread > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: context.primary, borderRadius: BorderRadius.circular(10)),
                    child: Text('${a.unread}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  )
                : Text('Switch', style: TextStyle(color: context.primary, fontWeight: FontWeight.w600)),
            onTap: () => Accounts.instance.switchTo(a.uid),
          ),
        if (others.length < Accounts.max - 1)
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.primary, width: 1.5)),
              child: Icon(Icons.add_rounded, color: context.primary),
            ),
            title: Text('Add account', style: TextStyle(color: context.primary, fontWeight: FontWeight.w600)),
            subtitle: Text('Use another number in BAATLY', style: TextStyle(color: bc.muted)),
            onTap: () => _confirmAdd(context),
          ),
      ]),
    );
  }
}

/// Small avatar on the chat list when two accounts are on this phone; tap to switch.
class AccountSwitchButton extends StatelessWidget {
  const AccountSwitchButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<SavedAccount>>(
      valueListenable: Accounts.instance.others,
      builder: (context, others, _) {
        if (others.isEmpty) return const SizedBox.shrink();
        final s = AppState.instance;
        final unread = others.fold<int>(0, (a, b) => a + b.unread);
        return IconButton(
          tooltip: 'Switch account',
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (sh) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: const [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text('Switch account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                AccountsSection(),
                SizedBox(height: 8),
              ]),
            ),
          ),
          icon: Stack(clipBehavior: Clip.none, children: [
            Avatar(initials: _ini(s.name.isEmpty ? 'You' : s.name), colorIndex: 2, size: 28, photo: s.myPhoto),
            if (unread > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(color: context.primary, borderRadius: BorderRadius.circular(8)),
                  child: Text('$unread', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        );
      },
    );
  }
}
