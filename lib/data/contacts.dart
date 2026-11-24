import 'package:flutter_contacts/flutter_contacts.dart';

import 'api.dart';

/// One person from the phone book (may have several numbers).
class PhoneContact {
  final String name;
  final String number; // as shown, e.g. +91 98992 72646
  final String e164;
  PhoneContact(this.name, this.number, this.e164);
}

/// A phone-book contact that is on BAATLY.
class BaatlyContact {
  final String userId;
  final String name; // phone-book name if saved, else profile name, else number
  final String phone;
  final String about;
  final String? key;
  BaatlyContact(this.userId, this.name, this.phone, this.about, this.key);
}

class ContactsResult {
  final bool permission;
  final List<BaatlyContact> onBaatly;
  final List<PhoneContact> invite;
  ContactsResult(this.permission, this.onBaatly, this.invite);
}

/// Reads the phone book and asks the server which numbers are on BAATLY.
/// The server matches the list and does not keep it.
class ContactBook {
  ContactBook._();
  static final ContactBook instance = ContactBook._();

  /// e164 -> name as saved on this phone.
  final Map<String, String> names = {};

  static String? toE164(String raw) {
    var s = raw.trim();
    final plus = s.startsWith('+');
    s = s.replaceAll(RegExp(r'\D'), '');
    if (s.isEmpty) return null;
    if (plus) return s.length >= 8 && s.length <= 15 ? '+$s' : null;
    if (s.startsWith('00')) return '+${s.substring(2)}';
    if (s.length == 11 && s.startsWith('0')) s = s.substring(1);
    if (s.length == 10 && RegExp(r'^[6-9]').hasMatch(s)) return '+91$s';
    if (s.length == 12 && s.startsWith('91')) return '+$s';
    return null;
  }

  static String pretty(String e164) {
    if (e164.startsWith('+91') && e164.length == 13) {
      return '+91 ${e164.substring(3, 8)} ${e164.substring(8)}';
    }
    return e164;
  }

  Future<ContactsResult> load() async {
    final st = await FlutterContacts.permissions.request(PermissionType.read);
    if (st.name != 'granted' && st.name != 'limited') {
      return ContactsResult(false, [], []);
    }
    final all = await FlutterContacts.getAll(properties: {ContactProperty.name, ContactProperty.phone});
    final people = <String, PhoneContact>{};
    for (final c in all) {
      final String? dn = c.displayName;
      final name = dn?.trim() ?? '';
      for (final ph in c.phones) {
        final String? norm = ph.normalizedNumber;
        final e = toE164(norm != null && norm.isNotEmpty ? norm : ph.number);
        if (e == null || people.containsKey(e)) continue;
        people[e] = PhoneContact(name.isEmpty ? pretty(e) : name, pretty(e), e);
        names[e] = name.isEmpty ? pretty(e) : name;
      }
    }
    final d = await Api.instance.request('POST', '/v1/contacts/match', {'numbers': people.keys.toList()});
    final on = <BaatlyContact>[];
    final onPhones = <String>{};
    for (final u in (d['users'] as List? ?? [])) {
      final m = u as Map<String, dynamic>;
      final phone = m['phone'] as String;
      onPhones.add(phone);
      final profile = (m['name'] as String?) ?? '';
      on.add(BaatlyContact(
        m['id'] as String,
        names[phone] ?? (profile.isNotEmpty ? profile : pretty(phone)),
        phone,
        (m['about'] as String?) ?? '',
        m['x25519'] as String?,
      ));
    }
    on.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final invite = people.values.where((p) => !onPhones.contains(p.e164)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ContactsResult(true, on, invite);
  }
}
