import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final bc = context.bc;
        Widget themeCard(ThemeMode m, String label, Color a, Color b) {
          final sel = s.themeMode == m;
          return Expanded(
            child: GestureDetector(
              onTap: () => s.setTheme(m),
              child: AnimatedContainer(
                duration: Mitti.fast,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bc.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: sel ? context.primary : bc.line, width: sel ? 2.5 : 1.5),
                ),
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 90,
                      child: Row(children: [
                        Expanded(child: Container(color: a)),
                        Expanded(child: Container(color: b)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(label, style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: bc.text)),
                ]),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: bc.bg,
          appBar: AppBar(backgroundColor: bc.bg, title: const Text('Appearance')),
          body: ListView(padding: const EdgeInsets.symmetric(horizontal: 14), children: [
            const SectionLabel('Theme'),
            Row(children: [
              themeCard(ThemeMode.light, 'Light', Mitti.cream, Mitti.cream),
              themeCard(ThemeMode.dark, 'Dark', Mitti.night, Mitti.night),
              themeCard(ThemeMode.system, 'System', Mitti.cream, Mitti.night),
            ]),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(color: bc.surface, borderRadius: BorderRadius.circular(18)),
              child: SwitchListTile(
                title: const Text('Reduce animations'),
                subtitle: const Text('Less motion, less battery'),
                value: s.reduceMotion,
                onChanged: (v) => s.toggle(() => s.reduceMotion = v),
              ),
            ),
          ]),
        );
      },
    );
  }
}
