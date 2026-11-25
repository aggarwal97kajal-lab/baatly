import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'chat_screen.dart';

/// A community as the server sends it.
class Community {
  final String id, name, about, announce;
  final bool admin, member;
  final List<({String id, String name, int members, bool joined})> groups;
  Community.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? '',
        about = j['about'] as String? ?? '',
        announce = j['announce'] as String,
        admin = j['admin'] == true,
        member = j['member'] == true,
        groups = [
          for (final g in (j['groups'] as List? ?? []))
            (
              id: (g as Map)['id'] as String,
              name: g['name'] as String? ?? 'Group',
              members: (g['members'] as num?)?.toInt() ?? 0,
              joined: g['joined'] == true,
            )
        ];
}

String _err(Object e) => e is ApiException ? e.message : 'Something went wrong. Try again.';

void _openGroup(BuildContext context, String gid) {
  final chat = Messenger.instance.chatById(gid);
  if (chat == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening… try again in a moment')));
    Messenger.instance.loadGroups();
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
}

/// List of communities you're in, plus "New community".
class CommunitiesScreen extends StatefulWidget {
  /// Shown as the home "Community" tab (no back arrow).
  final bool tab;
  const CommunitiesScreen({super.key, this.tab = false});
  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  List<Community>? _list;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.instance.request('GET', '/v1/communities');
      if (!mounted) return;
      setState(() {
        _error = null;
        _list = [for (final c in (d['communities'] as List? ?? [])) Community.fromJson((c as Map).cast<String, dynamic>())];
      });
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: !widget.tab, title: const Text('Communities')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: context.primary, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.groups_rounded, color: Colors.white),
            ),
            title: Text('New community', style: TextStyle(fontWeight: FontWeight.w700, color: bc.text)),
            subtitle: const Text('Bring related groups together'),
            onTap: () async {
              final c = await Navigator.of(context).push<Community>(MaterialPageRoute(builder: (_) => const NewCommunityScreen()));
              await _load();
              if (c != null && context.mounted) {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityScreen(id: c.id, initial: c)));
              }
            },
          ),
          const Divider(height: 1),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: bc.muted)))
          else if (_list == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_list!.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Communities keep related groups in one place, with an announcement group to reach everyone at once.',
                textAlign: TextAlign.center,
                style: TextStyle(color: bc.muted),
              ),
            )
          else
            for (final c in _list!)
              ListTile(
                leading: Avatar(initials: Messenger.initialsOf(c.name), colorIndex: c.id.codeUnits.fold<int>(0, (a, b) => a + b) % 7, size: 48),
                title: Text(c.name, style: TextStyle(fontWeight: FontWeight.w600, color: bc.text)),
                subtitle: Text('${c.groups.length} group${c.groups.length == 1 ? '' : 's'}'),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityScreen(id: c.id, initial: c)));
                  _load();
                },
              ),
        ]),
      ),
    );
  }
}

/// Groups you admin that aren't in a community yet.
List<Chat> _myAdminGroups() {
  final me = Messenger.instance.myId;
  return [
    for (final c in AppState.instance.chats)
      if (c.isRealGroup && !c.left && c.admins.contains(me)) c
  ];
}

class NewCommunityScreen extends StatefulWidget {
  const NewCommunityScreen({super.key});
  @override
  State<NewCommunityScreen> createState() => _NewCommunityScreenState();
}

class _NewCommunityScreenState extends State<NewCommunityScreen> {
  final _name = TextEditingController();
  final _about = TextEditingController();
  final _picked = <String>{};
  bool _busy = false;

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give the community a name')));
      return;
    }
    setState(() => _busy = true);
    try {
      final d = await Api.instance.request('POST', '/v1/communities', {'name': name, 'about': _about.text.trim(), 'groups': _picked.toList()});
      await Messenger.instance.loadGroups();
      if (!mounted) return;
      Navigator.of(context).pop(Community.fromJson((d['community'] as Map).cast<String, dynamic>()));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_err(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final groups = _myAdminGroups();
    return Scaffold(
      appBar: AppBar(title: const Text('New community')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _create,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded),
        label: const Text('Create'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
        TextField(
          controller: _name,
          maxLength: 100,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Community name'),
        ),
        TextField(
          controller: _about,
          maxLength: 500,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Description (optional)'),
        ),
        const SizedBox(height: 8),
        Text('An announcement group is made automatically. Only admins can post there, and everyone in the community gets it.',
            style: TextStyle(color: bc.muted, fontSize: 13)),
        const SizedBox(height: 16),
        const SectionLabel('Add your groups'),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text("You're not an admin of any group yet. You can add groups later.", style: TextStyle(color: bc.muted)),
          ),
        for (final g in groups)
          CheckboxListTile(
            value: _picked.contains(g.groupId),
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => v == true ? _picked.add(g.groupId!) : _picked.remove(g.groupId)),
            secondary: Avatar(initials: g.initials, colorIndex: g.colorIndex, size: 42, photo: g.photo),
            title: Text(g.name),
            subtitle: Text('${g.members.length} members'),
          ),
      ]),
    );
  }
}

class CommunityScreen extends StatefulWidget {
  final String id;
  final Community? initial;
  const CommunityScreen({super.key, required this.id, this.initial});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  late Community? _c = widget.initial;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.instance.request('GET', '/v1/communities/${widget.id}');
      if (mounted) setState(() => _c = Community.fromJson((d['community'] as Map).cast<String, dynamic>()));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_err(e))));
    }
  }

  Future<void> _run(String key, String method, String path, [Object? body]) async {
    setState(() => _busy.add(key));
    try {
      final d = await Api.instance.request(method, path, body);
      await Messenger.instance.loadGroups();
      if (mounted) setState(() => _c = Community.fromJson((d['community'] as Map).cast<String, dynamic>()));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_err(e))));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _addGroup() async {
    final c = _c!;
    final linked = {for (final g in c.groups) g.id, c.announce};
    final options = [for (final g in _myAdminGroups()) if (!linked.contains(g.groupId)) g];
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other groups where you are an admin')));
      return;
    }
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Add a group', style: TextStyle(fontWeight: FontWeight.w700))),
          for (final g in options)
            ListTile(
              leading: Avatar(initials: g.initials, colorIndex: g.colorIndex, size: 40, photo: g.photo),
              title: Text(g.name),
              onTap: () => Navigator.pop(s, g.groupId),
            ),
        ]),
      ),
    );
    if (pick != null) await _run('add', 'POST', '/v1/communities/${c.id}/groups', {'groupId': pick});
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final c = _c;
    if (c == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final mine = c.groups.where((g) => g.joined).toList();
    final others = c.groups.where((g) => !g.joined).toList();
    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Column(children: [
              Avatar(initials: Messenger.initialsOf(c.name), colorIndex: c.id.codeUnits.fold<int>(0, (a, b) => a + b) % 7, size: 84),
              const SizedBox(height: 12),
              Text(c.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: bc.text)),
              if (c.about.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(c.about, textAlign: TextAlign.center, style: TextStyle(color: bc.muted)),
              ],
            ]),
          ),
          if (c.member)
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: context.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.campaign_rounded, color: context.primary),
              ),
              title: Text('Announcements', style: TextStyle(fontWeight: FontWeight.w600, color: bc.text)),
              subtitle: Text(c.admin ? 'Post updates for everyone' : 'Updates from community admins'),
              onTap: () => _openGroup(context, c.announce),
            ),
          if (c.admin)
            ListTile(
              leading: CircleAvatar(backgroundColor: context.primary, child: _busy.contains('add')
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add_rounded, color: Colors.white)),
              title: const Text('Add existing group'),
              onTap: _busy.contains('add') ? null : _addGroup,
            ),
          if (mine.isNotEmpty) const SectionLabel('Groups you\'re in'),
          for (final g in mine)
            ListTile(
              leading: Avatar(initials: Messenger.initialsOf(g.name), colorIndex: g.id.codeUnits.fold<int>(0, (a, b) => a + b) % 7, size: 44),
              title: Text(g.name),
              subtitle: Text('${g.members} members'),
              onTap: () => _openGroup(context, g.id),
              onLongPress: c.admin ? () => _confirmRemove(g.id, g.name) : null,
            ),
          if (others.isNotEmpty) const SectionLabel('Other groups'),
          for (final g in others)
            ListTile(
              leading: Avatar(initials: Messenger.initialsOf(g.name), colorIndex: g.id.codeUnits.fold<int>(0, (a, b) => a + b) % 7, size: 44),
              title: Text(g.name),
              subtitle: Text('${g.members} members'),
              onLongPress: c.admin ? () => _confirmRemove(g.id, g.name) : null,
              trailing: c.member
                  ? FilledButton.tonal(
                      onPressed: _busy.contains(g.id) ? null : () => _run(g.id, 'POST', '/v1/communities/${c.id}/groups/${g.id}/join'),
                      child: _busy.contains(g.id) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Join'),
                    )
                  : null,
            ),
          if (c.admin)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Text('Tip: long-press a group to remove it from the community.', style: TextStyle(color: bc.muted, fontSize: 12.5)),
            ),
        ]),
      ),
    );
  }

  Future<void> _confirmRemove(String gid, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Remove "$name" from this community?'),
        content: const Text('The group itself stays as it is.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await _run(gid, 'DELETE', '/v1/communities/${_c!.id}/groups/$gid');
  }
}
