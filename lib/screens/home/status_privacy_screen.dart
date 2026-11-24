import 'package:flutter/material.dart';

import '../../config.dart';
import '../../data/api.dart';
import '../../data/app_state.dart';
import '../../data/contacts.dart';
import '../../data/messenger.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Who can see my status (like WhatsApp's Status privacy).
class StatusPrivacyScreen extends StatelessWidget {
  const StatusPrivacyScreen({super.key});

  Future<void> _edit(BuildContext context, int audience) async {
    final s = AppState.instance;
    final (title, current) = switch (audience) {
      1 => ('Hide status from…', s.statusExcept),
      2 => ('Share status with…', s.statusOnly),
      _ => ('Close friends', s.closeFriends),
    };
    final picked = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(builder: (_) => ContactPickerScreen(title: title, initial: current, excluding: audience == 1)),
    );
    if (picked == null) return;
    s.toggle(() {
      switch (audience) {
        case 1:
          s.statusExcept = picked;
        case 2:
          s.statusOnly = picked;
        default:
          s.closeFriends = picked;
      }
      s.statusAudience = audience;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        Widget option(int value, IconData icon, String title, {String? link}) {
          return InkWell(
            onTap: () => s.toggle(() => s.statusAudience = value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                CircleAvatar(radius: 26, backgroundColor: bc.raised, child: Icon(icon, color: bc.text)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontSize: 16, color: bc.text)),
                    if (link != null)
                      GestureDetector(
                        onTap: () => _edit(context, value),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(link, style: TextStyle(color: context.primary, fontWeight: FontWeight.w600)),
                            Icon(Icons.chevron_right_rounded, size: 18, color: context.primary),
                          ]),
                        ),
                      ),
                  ]),
                ),
                Radio<int>(value: value),
              ]),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Status privacy')),
          body: ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Text('Audience who can see my status', style: TextStyle(color: bc.muted)),
            ),
            RadioGroup<int>(
              groupValue: s.statusAudience,
              onChanged: (v) => s.toggle(() => s.statusAudience = v ?? 0),
              child: Column(children: [
                option(0, Icons.person_outline_rounded, 'My contacts'),
                option(1, Icons.person_remove_outlined, 'My contacts except…', link: '${s.statusExcept.length} excluded · Edit'),
                option(2, Icons.how_to_reg_outlined, 'Only share with…', link: '${s.statusOnly.length} included · Edit'),
                option(3, Icons.favorite_rounded, 'Close friends',
                    link: s.closeFriends.isEmpty ? 'Include people' : '${s.closeFriends.length} people · Edit'),
              ]),
            ),
            const Divider(height: 24),
            SwitchListTile(
              secondary: const Icon(Icons.repeat_rounded),
              title: const Text('Allow sharing'),
              subtitle: const Text('Let people who can see your status reshare and forward it.'),
              value: s.statusAllowSharing,
              onChanged: (v) => s.toggle(() => s.statusAllowSharing = v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Text(
                'Changes to your privacy settings won\'t affect status updates that you\'ve already sent.',
                style: TextStyle(fontSize: 12.5, color: bc.muted),
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// Pick BAATLY contacts with checkboxes. Returns the selected user ids.
class ContactPickerScreen extends StatefulWidget {
  final String title;
  final Set<String> initial;
  final bool excluding;
  const ContactPickerScreen({super.key, required this.title, required this.initial, this.excluding = false});
  @override
  State<ContactPickerScreen> createState() => _ContactPickerScreenState();
}

class _ContactPickerScreenState extends State<ContactPickerScreen> {
  late final Set<String> _sel = {...widget.initial};
  List<BaatlyContact>? _list;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!kHasBackend || !Api.instance.loggedIn) {
      setState(() => _error = 'Log in to choose contacts.');
      return;
    }
    try {
      final r = await ContactBook.instance.load();
      if (!mounted) return;
      if (!r.permission) {
        setState(() => _error = 'Allow BAATLY to read contacts to choose people.');
      } else {
        setState(() => _list = r.onBaatly);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't read contacts. ($e)");
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final list = (_list ?? []).where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q.toLowerCase())).toList();
    final all = _list != null && _list!.isNotEmpty && _list!.every((c) => _sel.contains(c.userId));
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title),
          Text('${_sel.length} selected', style: TextStyle(fontSize: 12, color: bc.muted)),
        ]),
        actions: [
          if (_list != null && _list!.isNotEmpty)
            IconButton(
              tooltip: all ? 'Clear all' : 'Select all',
              icon: Icon(all ? Icons.deselect_rounded : Icons.select_all_rounded),
              onPressed: () => setState(() => all ? _sel.clear() : _sel.addAll(_list!.map((c) => c.userId))),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: context.primary,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.pop(context, _sel),
        child: const Icon(Icons.check_rounded),
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: bc.muted))))
          : _list == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      onChanged: (v) => setState(() => _q = v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: bc.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  if (_list!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('None of your contacts are on BAATLY yet.', textAlign: TextAlign.center, style: TextStyle(color: bc.muted)),
                    ),
                  for (final c in list)
                    CheckboxListTile(
                      value: _sel.contains(c.userId),
                      onChanged: (v) => setState(() => v == true ? _sel.add(c.userId) : _sel.remove(c.userId)),
                      secondary: Avatar(initials: Messenger.initialsOf(c.name), colorIndex: c.userId.codeUnits.fold<int>(0, (a, b) => a + b) % 7, size: 42),
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(ContactBook.pretty(c.phone)),
                      activeColor: widget.excluding ? const Color(0xFFB3261E) : context.primary,
                    ),
                  const SizedBox(height: 90),
                ]),
    );
  }
}
