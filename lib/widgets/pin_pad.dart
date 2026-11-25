import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 6 dots + number keypad. Calls [onDone] with the PIN when 6 digits are in.
class PinPad extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? error;
  final bool busy;
  final Widget? extra;
  final Future<void> Function(String pin) onDone;
  const PinPad({super.key, required this.title, this.subtitle, this.error, this.busy = false, this.extra, required this.onDone});

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';

  void clear() => setState(() => _pin = '');

  Future<void> _tap(String k) async {
    if (widget.busy) return;
    if (k == '⌫') {
      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
      return;
    }
    if (_pin.length >= 6) return;
    setState(() => _pin += k);
    if (_pin.length == 6) {
      final p = _pin;
      await widget.onDone(p);
      if (mounted) setState(() => _pin = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    Widget key(String k) => Expanded(
          child: k.isEmpty
              ? const SizedBox(height: 64)
              : InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _tap(k),
                  child: SizedBox(
                    height: 64,
                    child: Center(
                      child: k == '⌫'
                          ? Icon(Icons.backspace_outlined, color: bc.text)
                          : Text(k, style: TextStyle(fontSize: 28, color: bc.text, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
        );
    return Column(children: [
      const SizedBox(height: 24),
      Text(widget.title, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: bc.text)),
      if (widget.subtitle != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
          child: Text(widget.subtitle!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: bc.muted, height: 1.4)),
        ),
      const SizedBox(height: 26),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < 6; i++)
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < _pin.length ? context.primary : Colors.transparent,
              border: Border.all(color: i < _pin.length ? context.primary : bc.muted, width: 2),
            ),
          ),
      ]),
      const SizedBox(height: 14),
      SizedBox(
        height: 22,
        child: widget.busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(widget.error ?? '', style: const TextStyle(color: Color(0xFFE5484D), fontSize: 13.5)),
      ),
      if (widget.extra != null) widget.extra!,
      const Spacer(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['', '0', '⌫'],
          ])
            Row(children: [for (final k in row) key(k)]),
        ]),
      ),
      const SizedBox(height: 18),
    ]);
  }
}
