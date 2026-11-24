import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'calls_tab.dart';
import 'chats_tab.dart';
import 'community_tab.dart';
import 'status_tab.dart';
import '../settings/you_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    AppState.instance.startDemoActivity();
  }

  static const _items = [
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chats'),
    (Icons.blur_circular_outlined, Icons.blur_circular_rounded, 'Status'),
    (Icons.call_outlined, Icons.call_rounded, 'Calls'),
    (Icons.groups_outlined, Icons.groups_rounded, 'Community'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'You'),
  ];

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    const pages = [ChatsTab(), StatusTab(), CallsTab(), CommunityTab(), YouTab()];
    return Scaffold(
      body: AnimatedSwitcher(
        duration: Mitti.fast,
        child: KeyedSubtree(key: ValueKey(_tab), child: pages[_tab]),
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
                    onTap: () => setState(() => _tab = i),
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
                        child: Icon(on ? it.$2 : it.$1, color: col, size: 22),
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
    );
  }
}
