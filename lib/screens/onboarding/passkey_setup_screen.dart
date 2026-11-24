import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'permissions_screen.dart';

/// Offered right after OTP registration: future logins use fingerprint /
/// screen lock instead of an SMS code.
class PasskeySetupScreen extends StatefulWidget {
  final Widget? next;
  const PasskeySetupScreen({super.key, this.next});
  @override
  State<PasskeySetupScreen> createState() => _PasskeySetupScreenState();
}

class _PasskeySetupScreenState extends State<PasskeySetupScreen> {
  bool _busy = false;
  bool _done = false;
  String? _error;

  void _next() => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => widget.next ?? const PermissionsScreen()));

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.createPasskey();
      setState(() => _done = true);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) _next();
    } on ApiException catch (e) {
      if (e.code != 'CANCELLED') setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    Widget point(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Icon(i, size: 20, color: context.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(t, style: TextStyle(fontSize: 13.5, color: bc.text))),
          ]),
        );
    return Scaffold(
      backgroundColor: bc.bg,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.symmetric(horizontal: 24), children: [
          const SizedBox(height: 50),
          Center(
            child: AnimatedSwitcher(
              duration: Mitti.medium,
              child: Container(
                key: ValueKey(_done),
                width: 150,
                height: 150,
                decoration: BoxDecoration(color: _done ? Mitti.success : bc.raised, shape: BoxShape.circle),
                child: Icon(_done ? Icons.check_rounded : Icons.fingerprint_rounded, size: 80, color: _done ? Colors.white : context.primary),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Text(_done ? 'Passkey ban gaya!' : 'Agli baar bina OTP ke login',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: bc.text)),
          const SizedBox(height: 10),
          Text('Passkey banayein — phir fingerprint ya screen lock se seedha login.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: bc.muted, height: 1.5)),
          const SizedBox(height: 28),
          point(Icons.bolt_rounded, 'SMS ka intezaar nahi — 1 second mein login'),
          point(Icons.shield_outlined, 'Phishing se safe: passkey sirf BAATLY ke liye kaam karta hai'),
          point(Icons.cloud_done_outlined, 'Google Password Manager mein save — naye phone par bhi milega'),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0x1FB3261E), borderRadius: BorderRadius.circular(12)),
              child: Text(_error!, style: const TextStyle(color: Mitti.error, fontSize: 13)),
            ),
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: _busy || _done ? null : _create,
            icon: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.fingerprint_rounded),
            label: const Text('Passkey banayein'),
          ),
          TextButton(
            onPressed: _busy ? null : _next,
            child: Text('Abhi nahi', style: TextStyle(color: bc.muted, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
