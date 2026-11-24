import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'profile_setup_screen.dart';

/// DEMO: no SMS is sent yet. Any 6 digits are accepted.
/// Real OTP (Firebase Auth) comes in Milestone 2.
class OtpScreen extends StatefulWidget {
  final String phone;
  const OtpScreen({super.key, required this.phone});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  int _left = 30;
  Timer? _timer;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _left = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) t.cancel();
      setState(() => _left = (_left - 1).clamp(0, 30));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_ctrl.text.length != 6 || _verifying) return;
    setState(() => _verifying = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    AppState.instance.phone = widget.phone;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ProfileSetupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final code = _ctrl.text;
    return Scaffold(
      backgroundColor: bc.bg,
      appBar: AppBar(backgroundColor: bc.bg),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            const SizedBox(height: 8),
            Text('Code daalein', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: bc.text)),
            const SizedBox(height: 8),
            Text('${widget.phone} pe bheja gaya.', style: TextStyle(fontSize: 13.5, color: bc.muted)),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Number badlein', style: TextStyle(fontSize: 13.5, color: context.primary, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 26),
            GestureDetector(
              onTap: () => _focus.requestFocus(),
              child: Stack(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (i) {
                    final filled = i < code.length;
                    final active = i == code.length;
                    return AnimatedContainer(
                      duration: Mitti.fast,
                      width: 48,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bc.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: active ? context.primary : (filled ? bc.text.withOpacity(0.25) : bc.line),
                          width: active ? 2 : 1.5,
                        ),
                      ),
                      child: Text(filled ? code[i] : '', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: bc.text)),
                    );
                  }),
                ),
                // Invisible field that actually receives input.
                Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    onChanged: (v) {
                      setState(() {});
                      if (v.length == 6) _verify();
                    },
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 22),
            Row(children: [
              Icon(Icons.timer_outlined, size: 18, color: context.primary),
              const SizedBox(width: 8),
              if (_left > 0)
                Text.rich(TextSpan(text: 'Code dobara bhejein ', children: [
                  TextSpan(text: '0:${_left.toString().padLeft(2, '0')}', style: TextStyle(color: bc.text, fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' mein'),
                ]), style: TextStyle(fontSize: 13, color: bc.muted))
              else
                GestureDetector(
                  onTap: _startTimer,
                  child: Text('Code dobara bhejein', style: TextStyle(fontSize: 13, color: context.primary, fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(Icons.science_outlined, size: 18, color: bc.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Demo build: abhi SMS nahi jaata. Koi bhi 6 digit daalein.',
                      style: TextStyle(fontSize: 12, color: bc.muted)),
                ),
              ]),
            ),
            const SizedBox(height: 30),
            AnimatedOpacity(
              opacity: code.length == 6 ? 1 : 0.45,
              duration: Mitti.fast,
              child: FilledButton(
                onPressed: code.length == 6 ? _verify : null,
                child: _verifying
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Verify karein'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
