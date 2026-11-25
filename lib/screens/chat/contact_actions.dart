import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' show FlutterContacts, Contact, Phone, Name, ContactProperty, PermissionType;

import '../../data/app_state.dart';
import '../../data/contacts.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import 'chat_tools.dart';

/// The phone contact saved for [e164], if any.
Future<Contact?> findPhoneContact(String e164) async {
  final st = await FlutterContacts.permissions.request(PermissionType.read);
  if (st.name != 'granted' && st.name != 'limited') return null;
  final all = await FlutterContacts.getAll(properties: {ContactProperty.name, ContactProperty.phone});
  for (final c in all) {
    for (final p in c.phones) {
      final n = p.normalizedNumber;
      if (ContactBook.toE164(n != null && n.isNotEmpty ? n : p.number) == e164) return c;
    }
  }
  return null;
}

/// Sends this person as a contact card to chats you pick.
Future<void> shareContactCard(BuildContext context, Chat chat) async {
  final phone = chat.phone ?? '';
  final md = <String, dynamic>{'name': chat.name, 'phone': phone, if (chat.peerId != null) 'uid': chat.peerId};
  await pickChatsAndSend(context, (c) => Messenger.instance.sendCard(c, MsgKind.contact, Map<String, dynamic>.from(md)));
}

/// Opens the person in the phone's Contacts app (or offers to save them).
Future<void> viewInAddressBook(BuildContext context, Chat chat) async {
  final phone = chat.phone;
  if (phone == null) return;
  final c = await findPhoneContact(phone);
  try {
    if (c?.id != null) {
      await FlutterContacts.native.showViewer(c!.id!);
    } else {
      await FlutterContacts.native.showCreator(contact: Contact(name: Name(first: chat.name), phones: [Phone(number: phone)]));
      await ContactBook.instance.load();
    }
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open Contacts")));
  }
}

/// Edit (or save) the contact without leaving BAATLY.
class EditContactScreen extends StatefulWidget {
  final Chat chat;
  const EditContactScreen({super.key, required this.chat});
  @override
  State<EditContactScreen> createState() => _EditContactScreenState();
}

class _EditContactScreenState extends State<EditContactScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  Contact? _existing;
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final phone = widget.chat.phone;
    Contact? c;
    if (phone != null) {
      try {
        c = await findPhoneContact(phone);
        if (c?.id != null) c = await FlutterContacts.get(c!.id!, properties: {ContactProperty.name, ContactProperty.phone});
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _existing = c;
      final n = c?.name;
      if (n != null && ((n.first ?? '').isNotEmpty || (n.last ?? '').isNotEmpty)) {
        _first.text = n.first ?? '';
        _last.text = n.last ?? '';
      } else {
        final parts = widget.chat.name.trim().split(RegExp(r'\s+'));
        _first.text = parts.first;
        _last.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    final first = _first.text.trim(), last = _last.text.trim();
    if (first.isEmpty && last.isEmpty) return;
    setState(() => _saving = true);
    try {
      final st = await FlutterContacts.permissions.request(PermissionType.readWrite);
      if (st.name != 'granted' && st.name != 'limited') throw Exception('perm');
      final name = Name(first: first, last: last.isEmpty ? null : last);
      if (_existing?.id != null) {
        await FlutterContacts.update(_existing!.copyWith(name: name));
      } else {
        await FlutterContacts.create(Contact(name: name, phones: [Phone(number: widget.chat.phone ?? '')]));
      }
      await ContactBook.instance.load();
      final full = [first, last].where((s) => s.isNotEmpty).join(' ');
      AppState.instance.toggle(() => widget.chat.name = full);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save. Allow BAATLY to edit contacts.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_existing == null ? 'New contact' : 'Edit contact'),
        actions: [
          TextButton(onPressed: _saving || _loading ? null : _save, child: const Text('Save')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              TextField(controller: _first, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'First name', prefixIcon: Icon(Icons.person_outline_rounded))),
              const SizedBox(height: 12),
              TextField(controller: _last, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Last name')),
              const SizedBox(height: 12),
              TextField(
                enabled: false,
                controller: TextEditingController(text: ContactBook.pretty(widget.chat.phone ?? '')),
                decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined)),
              ),
              const SizedBox(height: 12),
              Text('Saved to your phone contacts.', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
            ]),
    );
  }
}
