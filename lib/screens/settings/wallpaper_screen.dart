import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../theme/palettes.dart';

class WallpaperScreen extends StatelessWidget {
  const WallpaperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final bc = context.bc;
        return Scaffold(
          backgroundColor: bc.bg,
          appBar: AppBar(backgroundColor: bc.bg, title: const Text('Chat wallpaper')),
          body: GridView.count(
            crossAxisCount: 3,
            padding: const EdgeInsets.all(16),
            mainAxisSpacing: 14,
            crossAxisSpacing: 12,
            childAspectRatio: 0.52,
            children: [
              for (final w in Wallpaper.values)
                GestureDetector(
                  onTap: () => s.setWallpaper(w),
                  child: Column(children: [
                    Expanded(
                      child: AnimatedContainer(
                        duration: Mitti.fast,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: s.wallpaper == w ? context.primary : bc.line, width: s.wallpaper == w ? 3 : 1.5),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(fit: StackFit.expand, children: [
                            if (w.asset != null)
                              Image.asset(w.asset!, fit: BoxFit.cover)
                            else
                              Container(
                                color: const Color(0xFFF7EFE5),
                                child: w == Wallpaper.mittiDots
                                    ? Center(child: Icon(Icons.more_horiz_rounded, color: brandColor))
                                    : null,
                              ),
                            Positioned(
                              left: 8,
                              top: 30,
                              child: Container(width: 50, height: 14, decoration: BoxDecoration(color: w == Wallpaper.raat ? Mitti.nightRaised : Colors.white, borderRadius: BorderRadius.circular(7))),
                            ),
                            Positioned(
                              right: 8,
                              top: 52,
                              child: Container(width: 50, height: 14, decoration: BoxDecoration(color: brandColor, borderRadius: BorderRadius.circular(7))),
                            ),
                            if (s.wallpaper == w)
                              Positioned(
                                right: 6,
                                top: 6,
                                child: CircleAvatar(radius: 11, backgroundColor: brandColor, child: Icon(Icons.check_rounded, size: 15, color: Colors.white)),
                              ),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(w.label, style: TextStyle(fontSize: 12.5, fontWeight: s.wallpaper == w ? FontWeight.w700 : FontWeight.w500, color: bc.text)),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }
}
