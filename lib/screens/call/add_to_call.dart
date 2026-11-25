import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../data/calls.dart';
import '../../data/group_calls.dart';
import '../../data/messenger.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// "Add person" on a 1:1 call: pick up to 2 more people. The call becomes a small
/// group call (up to 4 people); the person you're talking to moves over by itself.
Future<void> addPersonToCall(BuildContext context, CallSession call) async {
  final people = AppState.instance.chats.where((c) => c.peerId != null && c.isReal && !c.isNotes && c.peerId != call.peerId).toList();
  final picked = <String>{};
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sh) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(children: [
                const Expanded(child: Text('Add to call', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                Text('${picked.length}/2', style: TextStyle(color: ctx.bc.muted)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Up to 4 people in a call', style: TextStyle(fontSize: 12.5, color: ctx.bc.muted)),
            ),
            Flexible(
              child: people.isEmpty
                  ? Padding(padding: const EdgeInsets.all(30), child: Text('No other BAATLY contacts yet', style: TextStyle(color: ctx.bc.muted)))
                  : ListView(shrinkWrap: true, children: [
                      for (final c in people)
                        CheckboxListTile(
                          value: picked.contains(c.peerId),
                          onChanged: (v) => set(() {
                            if (v == true && picked.length < 2) {
                              picked.add(c.peerId!);
                            } else {
                              picked.remove(c.peerId);
                            }
                          }),
                          secondary: Avatar(initials: c.initials, colorIndex: c.colorIndex, photo: Messenger.instance.photoOf(c.peerId!), size: 42),
                          title: Text(c.name),
                        ),
                    ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(onPressed: picked.isEmpty ? null : () => Navigator.pop(sh, true), child: const Text('Add')),
            ),
          ]),
        ),
      ),
    ),
  );
  if (ok != true || picked.isEmpty) return;
  if (CallService.instance.current != call) return;
  await GroupCallService.instance.startAdhoc(
    people: [call.peerId, ...picked],
    name: '${call.peerName} + ${picked.length}',
    video: call.video,
    upgrade: call.id,
    upgradePeer: call.peerId,
  );
}
