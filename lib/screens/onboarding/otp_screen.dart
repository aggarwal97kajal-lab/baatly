import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';
import '../../data/api.dart';
import '../../data/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../home/home_shell.dart';
import 'passkey_setup_screen.dart';
import 'profile_setup_screen.dart';

/// Verifies the SMS code via the BAATLY server (Message Central does the actual
/// sending and checking). Without a backend configured it runs the offline demo.
class OtpScreen extends StatefulWidget {
  final String phone;
  final String countryCode;
  final String number;
  final OtpRequest? request;
  const OtpScreen({super.key, required this.phone, required this.countryCode, required this.number, this.request});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  int _left = 30;
  Timer? _timer;
  bool _verifying = false;
  String? _error;
  OtpRequest? _req;

  bool get _demo => !kHasBackend || (_req?.demo ?? false);

  @override
  void initState() {
    super.initState();
    _req = widget.request;
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

  Future<void> _resend() async {
    if (!kHasBackend) return _startTimer();
    try {
      final r = await Api.instance.sendOtp(widget.countryCode, widget.number);
      setState(() {
        _req = r;
        _error = null;
        _ctrl.clear();
      });
      _startTimer();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _verify() async {
    if (_ctrl.text.length != 6 || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    final s = AppState.instance;
    try {
      if (!kHasBackend) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        s.phone = widget.phone;
        _go(const ProfileSetupScreen());
        return;
      }
      final r = await Api.instance.verifyOtp(_req!.requestId, _ctrl.text);
      s.phone = r.user.phone;
      if (r.user.name.isEmpty || r.user.username == null) {
        _go(ProfileSetupScreen(offerPasskey: !r.hasPasskey));
      } else if (!r.hasPasskey) {
        s.finishOnboarding(name: r.user.name, username: r.user.username!, about: r.user.about);
        _go(const PasskeySetupScreen());
      } else {
        s.finishOnboarding(name: r.user.name, username: r.user.username!, about: r.user.about);
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeShell()), (_) => false);
      }
    } on ApiException catch (e) {
      HapticFeedback.mediumImpact();
      setState(() {
        _error = e.message;
        _ctrl.clear();
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _go(Widget w) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => w));
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
            Text('Enter code', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: bc.text)),
            const SizedBox(height: 8),
            Text('We sent a 6-digit code to ${widget.phone}.', style: TextStyle(fontSize: 13.5, color: bc.muted)),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Change number', style: TextStyle(fontSize: 13.5, color: context.primary, fontWeight: FontWeight.w700)),
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
                    final err = _error != null;
                    return AnimatedContainer(
                      duration: Mitti.fast,
                      width: 48,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bc.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: err ? Mitti.error : (active ? context.primary : (filled ? bc.text.withOpacity(0.25) : bc.line)),
                          width: active || err ? 2 : 1.5,
                        ),
                      ),
                      child: Text(filled ? code[i] : '', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: bc.text)),
                    );
                  }),
                ),
                Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    onChanged: (v) {
                      setState(() => _error = null);
                      if (v.length == 6) _verify();
                    },
                  ),
                ),
              ]),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, size: 18, color: Mitti.error),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_error!, style: const TextStyle(fontSize: 13, color: Mitti.error, fontWeight: FontWeight.w500))),
                ]),
              ),
            const SizedBox(height: 22),
            Row(children: [
              Icon(Icons.timer_outlined, size: 18, color: context.primary),
              const SizedBox(width: 8),
              if (_left > 0)
                Text.rich(TextSpan(text: 'Resend code in ', children: [
                  TextSpan(text: '0:${_left.toString().padLeft(2, '0')}', style: TextStyle(color: bc.text, fontWeight: FontWeight.w700)),
                  const TextSpan(text: ''),
                ]), style: TextStyle(fontSize: 13, color: bc.muted))
              else
                GestureDetector(
                  onTap: _resend,
                  child: Text('Resend code', style: TextStyle(fontSize: 13, color: context.primary, fontWeight: FontWeight.w700)),
                ),
            ]),
            if (_demo) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: bc.raised, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(Icons.science_outlined, size: 18, color: bc.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      kHasBackend
                          ? 'Test mode: SMS is not connected yet. Enter 123456.'
                          : 'Demo build: no SMS is sent. Enter any 6 digits.',
                      style: TextStyle(fontSize: 12, color: bc.muted),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 30),
            AnimatedOpacity(
              opacity: code.length == 6 ? 1 : 0.45,
              duration: Mitti.fast,
              child: FilledButton(
                onPressed: code.length == 6 ? _verify : null,
                child: _verifying
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Verify'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
