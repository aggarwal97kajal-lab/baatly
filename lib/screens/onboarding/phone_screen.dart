import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config.dart';
import '../../data/api.dart';
import '../../data/app_state.dart';
import '../../theme/app_theme.dart';
import '../home/home_shell.dart';
import 'otp_screen.dart';
import 'profile_setup_screen.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});
  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _ctrl = TextEditingController();
  String _code = '+91';
  bool _busy = false;
  bool _passkeyBusy = false;

  bool get _valid => _ctrl.text.replaceAll(' ', '').length == 10;

  static const _countries = [
    ('🇮🇳', 'India', '+91'),
    ('🇳🇵', 'Nepal', '+977'),
    ('🇧🇩', 'Bangladesh', '+880'),
    ('🇦🇪', 'UAE', '+971'),
    ('🇺🇸', 'USA', '+1'),
    ('🇬🇧', 'UK', '+44'),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _pickCountry() async {
    final bc = context.bc;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          for (final c in _countries)
            ListTile(
              leading: Text(c.$1, style: const TextStyle(fontSize: 24)),
              title: Text(c.$2),
              trailing: Text(c.$3, style: TextStyle(color: bc.muted)),
              onTap: () => Navigator.pop(context, c.$3),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
    if (picked != null) setState(() => _code = picked);
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text(m)));

  Future<void> _continue() async {
    final number = _ctrl.text;
    if (!kHasBackend) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => OtpScreen(phone: '$_code $number', countryCode: _code, number: number)));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await Api.instance.sendOtp(_code, number);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OtpScreen(phone: '$_code $number', countryCode: _code, number: number, request: r)));
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _passkey() async {
    setState(() => _passkeyBusy = true);
    try {
      final r = await Api.instance.loginWithPasskey();
      if (!mounted) return;
      final s = AppState.instance;
      s.phone = r.user.phone;
      if (r.user.name.isEmpty || r.user.username == null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ProfileSetupScreen()));
        return;
      }
      s.finishOnboarding(name: r.user.name, username: r.user.username ?? '', about: r.user.about);
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeShell()), (_) => false);
    } on ApiException catch (e) {
      if (e.code != 'CANCELLED') _toast(e.message);
    } finally {
      if (mounted) setState(() => _passkeyBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final flag = _countries.firstWhere((c) => c.$3 == _code).$1;
    return Scaffold(
      appBar: AppBar(backgroundColor: bc.bg),
      backgroundColor: bc.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            const SizedBox(height: 8),
            Text('Enter your\nphone number', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: bc.text, height: 1.25)),
            const SizedBox(height: 10),
            Text('We\'ll text you a 6-digit code to verify it.', style: TextStyle(fontSize: 13, color: bc.muted)),
            const SizedBox(height: 28),
            Row(children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _pickCountry,
                child: Container(
                  height: 58,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: bc.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: bc.line, width: 1.5),
                  ),
                  child: Row(children: [
                    Text(flag, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 6),
                    Text(_code, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: bc.text)),
                    Icon(Icons.keyboard_arrow_down_rounded, color: bc.muted),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1, color: bc.text),
                  decoration: InputDecoration(
                    hintText: '98765 43210',
                    filled: true,
                    fillColor: bc.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: bc.line, width: 1.5)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: context.primary, width: 2)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Icon(Icons.info_outline_rounded, size: 16, color: bc.muted),
              const SizedBox(width: 6),
              Expanded(child: Text('Carrier SMS rates may apply.', style: TextStyle(fontSize: 12, color: bc.muted))),
            ]),
            const SizedBox(height: 40),
            AnimatedOpacity(
              opacity: _valid ? 1 : 0.45,
              duration: const Duration(milliseconds: 200),
              child: FilledButton(
                onPressed: _valid && !_busy ? _continue : null,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Continue'),
              ),
            ),
            if (kHasBackend) ...[
              const SizedBox(height: 22),
              Row(children: [
                Expanded(child: Divider(color: bc.line)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('already have an account?', style: TextStyle(fontSize: 12, color: bc.muted))),
                Expanded(child: Divider(color: bc.line)),
              ]),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _passkeyBusy ? null : _passkey,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: const StadiumBorder(),
                  side: BorderSide(color: context.primary, width: 1.5),
                  foregroundColor: context.primary,
                ),
                icon: _passkeyBusy
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.primary))
                    : const Icon(Icons.fingerprint_rounded),
                label: const Text('Log in with passkey', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
