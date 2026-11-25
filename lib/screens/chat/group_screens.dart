import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api.dart';
import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chat_dialogs.dart';
import '../../widgets/common.dart';
import '../home/status_privacy_screen.dart';
import 'chat_screen.dart';
import 'starred_screen.dart';
import 'chat_tools.dart';
import '../../widgets/photo_viewer.dart';

/// New group: pick members, then name it.
Future<void> startNewGroup(BuildContext context) async {
  final ids = await Navigator.of(context).push<Set<String>>(
    MaterialPageRoute(builder: (_) => const ContactPickerScreen(title: 'Add members', initial: {})),
  );
  if (ids == null || ids.isEmpty || !context.mounted) return;
  await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => _GroupNameScreen(members: ids.toList())));
}

class _GroupNameScreen extends StatefulWidget {
  final List<String> members;
  const _GroupNameScreen({required this.members});
  @override
  State<_GroupNameScreen> createState() => _GroupNameScreenState();
}

class _GroupNameScreenState extends State<_GroupNameScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final chat = await Messenger.instance.createGroup(name, widget.members);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: context.primary,
        foregroundColor: Colors.white,
        onPressed: _busy ? null : _create,
        child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Icon(Icons.check_rounded),
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          CircleAvatar(radius: 30, backgroundColor: bc.raised, child: Icon(Icons.groups_rounded, color: bc.muted, size: 30)),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _name,
              autofocus: true,
              maxLength: 100,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Group name'),
              onSubmitted: (_) => _create(),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Members: ${widget.members.length}', style: TextStyle(color: bc.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final id in widget.members) Chip(label: Text(Messenger.instance.nameFor(id))),
        ]),
      ]),
    );
  }
}

/// Group info: members, admins, add/remove, rename, exit.
class GroupInfoScreen extends StatelessWidget {
  final Chat chat;
  const GroupInfoScreen({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final ms = Messenger.instance;
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final me = ms.myId;
        final iAmAdmin = chat.admins.contains(me);
        final canEdit = ms.canEditGroup(chat);
        final members = [...chat.members]..sort((a, b) {
            if (a == me) return -1;
            if (b == me) return 1;
            final aa = chat.admins.contains(a), ba = chat.admins.contains(b);
            if (aa != ba) return aa ? -1 : 1;
            return ms.nameFor(a).toLowerCase().compareTo(ms.nameFor(b).toLowerCase());
          });

        Future<void> run(Future<void> Function() f) async {
          try {
            await f();
          } on ApiException catch (e) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
          }
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Group info')),
          body: ListView(children: [
            const SizedBox(height: 12),
            Center(
              child: GestureDetector(
                onTap: !canEdit
                    ? () => PhotoViewerScreen.open(context, chat.photo, chat.name)
                    : () async {
                        final choice = await showModalBottomSheet<String>(
                          context: context,
                          showDragHandle: true,
                          builder: (sheet) => SafeArea(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              if (chat.photo != null)
                                ListTile(leading: const Icon(Icons.fullscreen_rounded), title: const Text('View icon'), onTap: () => Navigator.pop(sheet, 'view')),
                              ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Change icon'), onTap: () => Navigator.pop(sheet, 'change')),
                              if (chat.photo != null)
                                ListTile(
                                  leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB3261E)),
                                  title: const Text('Remove icon', style: TextStyle(color: Color(0xFFB3261E))),
                                  onTap: () => Navigator.pop(sheet, 'remove'),
                                ),
                              const SizedBox(height: 8),
                            ]),
                          ),
                        );
                        if (choice == 'view') {
                          if (context.mounted) PhotoViewerScreen.open(context, chat.photo, chat.name);
                          return;
                        }
                        if (choice == 'remove') {
                          await run(() => ms.removeGroupPhoto(chat));
                          return;
                        }
                        if (choice != 'change') return;
                        final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
                        if (f == null) return;
                        final c = await ImageCropper().cropImage(
                          sourcePath: f.path,
                          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
                          maxWidth: 1080,
                          maxHeight: 1080,
                          compressQuality: 85,
                          uiSettings: [AndroidUiSettings(toolbarTitle: 'Group icon', lockAspectRatio: true, cropStyle: CropStyle.circle, hideBottomControls: true)],
                        );
                        if (c == null) return;
                        await run(() => ms.setGroupPhoto(chat, c.path));
                      },
                child: Stack(clipBehavior: Clip.none, children: [
                  Avatar(initials: chat.initials, colorIndex: chat.colorIndex, photo: chat.photo, size: 96),
                  if (canEdit)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(radius: 16, backgroundColor: context.primary, child: const Icon(Icons.photo_camera_rounded, size: 16, color: Colors.white)),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text(chat.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: bc.text))),
              if (canEdit)
                IconButton(
                  icon: Icon(Icons.edit_rounded, size: 20, color: bc.muted),
                  onPressed: () async {
                    final c = TextEditingController(text: chat.name);
                    final name = await showDialog<String>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Group name'),
                        content: TextField(controller: c, autofocus: true, maxLength: 100),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('OK')),
                        ],
                      ),
                    );
                    if (name != null && name.isNotEmpty && name != chat.name) await run(() => ms.renameGroup(chat, name));
                  },
                ),
            ]),
            Text('Group · ${chat.members.length} members', textAlign: TextAlign.center, style: TextStyle(color: bc.muted)),
            const SizedBox(height: 12),
            ListTile(
              title: Text(chat.description.isEmpty ? (canEdit ? 'Add group description' : 'No description') : chat.description,
                  style: TextStyle(color: chat.description.isEmpty ? context.primary : bc.text)),
              subtitle: chat.description.isEmpty ? null : Text('Group description', style: TextStyle(color: bc.muted, fontSize: 12)),
              trailing: canEdit ? Icon(Icons.edit_outlined, size: 18, color: bc.muted) : null,
              onTap: !canEdit
                  ? null
                  : () async {
                      final c = TextEditingController(text: chat.description);
                      final text = await showDialog<String>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: const Text('Group description'),
                          content: TextField(controller: c, autofocus: true, maxLength: 500, minLines: 2, maxLines: 6),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
                          ],
                        ),
                      );
                      if (text != null && text != chat.description) await run(() => ms.setGroupDescription(chat, text));
                    },
            ),
            if (iAmAdmin && !chat.left) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('Group settings', style: TextStyle(color: bc.muted, fontWeight: FontWeight.w600)),
              ),
              SwitchListTile(
                secondary: Icon(Icons.edit_note_rounded, color: context.primary),
                title: const Text('Only admins can edit group info'),
                subtitle: const Text('Name, icon, description and pinned messages'),
                value: chat.editInfo == 'admins',
                onChanged: (v) => run(() => ms.setGroupSettings(chat, editInfo: v ? 'admins' : 'all')),
              ),
              SwitchListTile(
                secondary: Icon(Icons.campaign_outlined, color: context.primary),
                title: const Text('Only admins can send messages'),
                value: chat.sendMessages == 'admins',
                onChanged: (v) => run(() => ms.setGroupSettings(chat, sendMessages: v ? 'admins' : 'all')),
              ),
            ],
            const SizedBox(height: 4),
            ListTile(
              leading: Icon(Icons.notifications_off_outlined, color: context.primary),
              title: const Text('Mute notifications'),
              subtitle: Text(muteLabel(chat)),
              onTap: () => showMuteDialog(context, chat),
            ),
            ListTile(
              leading: Icon(Icons.perm_media_outlined, color: context.primary),
              title: const Text('Media, links and docs'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatMediaScreen(chat: chat))),
            ),
            ListTile(
              leading: Icon(Icons.star_outline_rounded, color: context.primary),
              title: const Text('Starred messages'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StarredScreen(only: chat))),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('${chat.members.length} members', style: TextStyle(color: bc.muted, fontWeight: FontWeight.w600)),
            ),
            if (iAmAdmin && !chat.left)
              ListTile(
                leading: CircleAvatar(backgroundColor: context.primary, child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white)),
                title: const Text('Add members', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () async {
                  final ids = await Navigator.of(context).push<Set<String>>(
                    MaterialPageRoute(
                      builder: (_) => ContactPickerScreen(title: 'Add members', initial: const {}, already: chat.members.toSet(), alreadyLabel: 'Already in this group'),
                    ),
                  );
                  final add = (ids ?? {}).where((x) => !chat.members.contains(x)).toList();
                  if (add.isNotEmpty) await run(() => ms.addMembers(chat, add));
                },
              ),
            for (final u in members)
              ListTile(
                leading: Avatar(initials: Messenger.initialsOf(ms.nameFor(u)), colorIndex: u.length % 7, photo: u == me ? AppState.instance.myPhoto : ms.photoOf(u), size: 42),
                title: Text(u == me ? 'You' : ms.nameFor(u), style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: chat.admins.contains(u)
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: context.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                        child: Text('Group admin', style: TextStyle(fontSize: 11.5, color: context.primary, fontWeight: FontWeight.w600)),
                      )
                    : null,
                onTap: u == me
                    ? null
                    : () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          builder: (sheet) => SafeArea(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              ListTile(
                                leading: const Icon(Icons.chat_bubble_outline_rounded),
                                title: Text('Message ${ms.nameFor(u)}'),
                                onTap: () {
                                  Navigator.pop(sheet);
                                  final c = ms.chatWithUser(u, ms.nameFor(u), '', null);
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: c)));
                                },
                              ),
                              if (iAmAdmin && !chat.left) ...[
                                ListTile(
                                  leading: const Icon(Icons.admin_panel_settings_outlined),
                                  title: Text(chat.admins.contains(u) ? 'Dismiss as admin' : 'Make group admin'),
                                  onTap: () {
                                    Navigator.pop(sheet);
                                    run(() => ms.setAdmin(chat, u, !chat.admins.contains(u)));
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.person_remove_outlined, color: Color(0xFFB3261E)),
                                  title: Text('Remove ${ms.nameFor(u)}', style: const TextStyle(color: Color(0xFFB3261E))),
                                  onTap: () {
                                    Navigator.pop(sheet);
                                    run(() => ms.removeMember(chat, u));
                                  },
                                ),
                              ],
                              const SizedBox(height: 8),
                            ]),
                          ),
                        ),
              ),
            const Divider(),
            if (!chat.left)
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Color(0xFFB3261E)),
                title: const Text('Exit group', style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w600)),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: Text('Exit "${chat.name}"?'),
                      content: const Text("You won't get new messages from this group."),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Exit', style: TextStyle(color: Color(0xFFB3261E)))),
                      ],
                    ),
                  );
                  if (ok == true) await run(() => ms.leaveGroup(chat));
                },
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text("You're no longer a member of this group.", style: TextStyle(color: bc.muted)),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFB3261E)),
                title: const Text('Delete group', style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w600)),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: Text('Delete "${chat.name}"?'),
                      content: const Text('The group and its messages will be removed from this phone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete', style: TextStyle(color: Color(0xFFB3261E)))),
                      ],
                    ),
                  );
                  if (ok != true || !context.mounted) return;
                  AppState.instance.deleteChat(chat);
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
            ],
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }
}
