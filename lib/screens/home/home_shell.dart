import 'dart:async';
import 'package:flutter/material.dart';

import '../../config.dart';
import '../../data/api.dart';
import '../../data/backup.dart';
import 'package:app_links/app_links.dart';
import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../data/status_service.dart';
import '../../data/notifier.dart';
import '../../data/calls.dart';
import '../chat/chat_screen.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'calls_tab.dart';
import '../settings/qr_screen.dart';
import 'chats_tab.dart';
import 'community_tab.dart';
import 'status_tab.dart';
import '../settings/chats_settings.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  final _pages = PageController();

  void _go(int i) {
    setState(() => _tab = i);
    _pages.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    if (i == 1) StatusService.instance.refresh();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Notifier.instance.onOpenChat = _openFromNotification;
    Notifier.instance.onCallBack = _callBack;
    Notifier.instance.onOpenCall = (id) {
      Notifier.instance.pendingCall = null;
      CallService.instance.openIncoming(id);
    };
    if (kHasBackend && Api.instance.loggedIn) {
      Messenger.instance.start().then((_) async {
        await BackupService.instance.load();
        unawaited(BackupService.instance.maybeAuto());
        _listenLinks();
        if (mounted) unawaited(offerRestore(context));
        final p = Notifier.instance.pendingChat;
        if (p != null) _openFromNotification(p);
        final cb = Notifier.instance.pendingCallBack;
        if (cb != null) _callBack(cb.peer, cb.video);
        unawaited(CallService.instance.syncRecent());
        final call = Notifier.instance.pendingCall;
        if (call != null) {
          Notifier.instance.pendingCall = null;
          CallService.instance.openIncoming(call);
        }
      });
    } else {
      AppState.instance.startDemoActivity();
    }
  }

  Future<void> _callBack(String peer, bool video) async {
    Notifier.instance.pendingCallBack = null;
    final chat = await Messenger.instance.chatForUser(peer);
    if (chat != null) await CallService.instance.start(chat, video: video);
  }

  void _openFromNotification(String id) {
    Notifier.instance.pendingChat = null;
    final chat = Messenger.instance.chatById(id);
    if (chat == null || !mounted) return;
    AppState.instance.openChat(chat);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _links?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Messenger.instance.active) return;
    if (state == AppLifecycleState.paused) Messenger.instance.pause();
    if (state == AppLifecycleState.resumed) {
      Messenger.instance.resume();
      unawaited(BackupService.instance.maybeAuto());
      unawaited(CallService.instance.syncRecent());
    }
  }

  static const _items = [
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chats'),
    (Icons.blur_circular_outlined, Icons.blur_circular_rounded, 'Updates'),
    (Icons.call_outlined, Icons.call_rounded, 'Calls'),
    (Icons.groups_outlined, Icons.groups_rounded, 'Community'),
  ];

  StreamSubscription<Uri>? _links;
  String? _lastLink;

  /// Call links: baatly://call/<user id>?v=1 → call that person.
  void _listenLinks() {
    _links ??= AppLinks().uriLinkStream.listen((u) async {
      if (u.scheme != 'baatly' || u.pathSegments.isEmpty) return;
      final key = u.toString();
      if (key == _lastLink) return;
      _lastLink = key;
      if (u.host == 'u') {
        if (mounted) openUserFromQr(context, u.pathSegments.first);
        return;
      }
      if (u.host != 'call') return;
      final id = u.pathSegments.first;
      if (id == Messenger.instance.myId) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This is your own call link')));
        return;
      }
      final chat = await Messenger.instance.chatForUser(id);
      if (chat == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open this call link")));
        return;
      }
      CallService.instance.start(chat, video: u.queryParameters['v'] == '1');
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    const pages = [ChatsTab(), StatusTab(), CallsTab(), CommunityTab()];
    // Back button on any other tab goes to Chats first; on Chats it leaves the app.
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _tab != 0) _go(0);
      },
      child: Scaffold(
      body: PageView(
        controller: _pages,
        onPageChanged: (i) {
          setState(() => _tab = i);
          if (i == 1) StatusService.instance.refresh();
        },
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: bc.surface, border: Border(top: BorderSide(color: bc.line))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Row(
              children: List.generate(_items.length, (i) {
                final on = i == _tab;
                final it = _items[i];
                final col = on ? context.primary : bc.muted;
                return Expanded(
                  child: InkWell(
                    onTap: () => _go(i),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      AnimatedContainer(
                        duration: Mitti.fast,
                        curve: Curves.easeOut,
                        width: on ? 54 : 32,
                        height: 30,
                        decoration: BoxDecoration(
                          color: on ? context.primary.withOpacity(0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                          Icon(on ? it.$2 : it.$1, color: col, size: 22),
                          if (i == 0)
                            ListenableBuilder(
                              listenable: AppState.instance,
                              builder: (context, _) {
                                final n = AppState.instance.chats.where((c) => c.unread > 0 && !c.archived).length;
                                if (n == 0) return const SizedBox.shrink();
                                return Positioned(
                                  top: -4,
                                  right: on ? 6 : -8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    constraints: const BoxConstraints(minWidth: 18),
                                    decoration: BoxDecoration(color: context.primary, borderRadius: BorderRadius.circular(9)),
                                    child: Text('$n', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                                  ),
                                );
                              },
                            ),
                        ]),
                      ),
                      const SizedBox(height: 3),
                      Text(it.$3, style: TextStyle(fontSize: 10.5, color: col, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                    ]),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    ),
    );
  }
}
