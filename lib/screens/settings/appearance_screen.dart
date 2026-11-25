import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/palettes.dart';
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
        final pal = paletteAt(s.palette);
        final lightBg = Surfaces.of(pal, false).bg;
        final darkBg = Surfaces.of(pal, true).bg;
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
              themeCard(ThemeMode.light, 'Light', lightBg, lightBg),
              themeCard(ThemeMode.dark, 'Dark', darkBg, darkBg),
              themeCard(ThemeMode.system, 'System', lightBg, darkBg),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Colour'),
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.78,
              children: [
                for (var i = 0; i < palettes.length; i++)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => s.setPalette(i),
                    child: Column(children: [
                      AnimatedContainer(
                        duration: Mitti.fast,
                        width: 48,
                        height: 48,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.isDark ? palettes[i].dark : palettes[i].light,
                          gradient: palettes[i].linear,
                          border: s.palette == i ? Border.all(color: bc.text, width: 2.5) : null,
                        ),
                        child: s.palette == i ? Icon(Icons.check_rounded, color: palettes[i].onPrimary) : null,
                      ),
                      const SizedBox(height: 5),
                      Text(palettes[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: s.palette == i ? bc.text : bc.muted, fontWeight: s.palette == i ? FontWeight.w700 : FontWeight.w400)),
                    ]),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Material(
              color: bc.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              clipBehavior: Clip.antiAlias,
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
