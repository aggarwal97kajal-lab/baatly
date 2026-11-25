import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A light "tick" on every tap of something tappable (buttons, tabs, list
/// rows, menu items…) across the whole app — like WhatsApp. Taps on empty
/// space, scrolling and typing don't vibrate.
class TapHaptics {
  static final _down = <int, (Offset, Duration)>{};

  static void install() {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  static void _route(PointerEvent e) {
    if (e is PointerDownEvent) {
      _down[e.pointer] = (e.position, e.timeStamp);
    } else if (e is PointerUpEvent) {
      final d = _down.remove(e.pointer);
      if (d == null) return;
      if ((e.position - d.$1).distance > 16) return; // a drag / scroll
      if (e.timeStamp - d.$2 > const Duration(milliseconds: 450)) return; // long press has its own
      if (_tappable(e.position, e.viewId)) HapticFeedback.selectionClick();
    } else if (e is PointerCancelEvent) {
      _down.remove(e.pointer);
    }
  }

  static bool _tappable(Offset pos, int viewId) {
    try {
      final r = HitTestResult();
      WidgetsBinding.instance.hitTestInView(r, pos, viewId);
      for (final entry in r.path) {
        final t = entry.target;
        if (t is RenderSemanticsGestureHandler && t.onTap != null) return true;
        if (t is RenderEditable) return false;
      }
    } catch (_) {}
    return false;
  }
}
