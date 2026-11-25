import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pin_pad.dart';

/// Settings › Account › Two-step verification.
class TwoStepScreen extends StatefulWidget {
  const TwoStepScreen({super.key});

  @override
  State<TwoStepScreen> createState() => _TwoStepScreenState();
}

class _TwoStepScreenState extends State<TwoStepScreen> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await Api.instance.twoStepEnabled();
      if (mounted) setState(() => _on = v);
    } catch (_) {
      if (mounted) setState(() => _on = false);
    }
  }

  Future<void> _set() async {
    final pin = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const NewPinScreen(title: 'Create a 6-digit PIN', subtitle: "You'll need it when you log in to BAATLY on a new phone.")));
    if (pin == null) return;
    try {
      await Api.instance.setTwoStep(pin);
      if (!mounted) return;
      setState(() => _on = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Two-step verification is on')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : "Couldn't save. Check your connection.")));
    }
  }

  Future<void> _off() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Turn off two-step verification?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Turn off')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.instance.offTwoStep();
      if (mounted) setState(() => _on = false);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't turn off. Check your connection.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Scaffold(
      backgroundColor: bc.bg,
      appBar: AppBar(title: const Text('Two-step verification')),
      body: _on == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(color: context.primary.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(Icons.password_rounded, size: 40, color: context.primary),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _on!
                    ? 'Two-step verification is on. You\'ll need your PIN when you log in to BAATLY on a new phone.'
                    : 'For extra security, set a 6-digit PIN. After the SMS code, BAATLY will ask for it when you log in on a new phone. Someone with your SIM still can\'t get into your account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: bc.muted, height: 1.45),
              ),
              const SizedBox(height: 26),
              if (!_on!) FilledButton(onPressed: _set, child: const Text('Turn on')),
              if (_on!) ...[
                ListTile(leading: const Icon(Icons.password_rounded), title: const Text('Change PIN'), onTap: _set),
                ListTile(leading: const Icon(Icons.block_rounded, color: Color(0xFFE5484D)), title: const Text('Turn off', style: TextStyle(color: Color(0xFFE5484D))), onTap: _off),
              ],
            ]),
    );
  }
}

/// Enter a new 6-digit PIN twice. Pops with the PIN.
class NewPinScreen extends StatefulWidget {
  final String title;
  final String? subtitle;
  const NewPinScreen({super.key, required this.title, this.subtitle});

  @override
  State<NewPinScreen> createState() => _NewPinScreenState();
}

class _NewPinScreenState extends State<NewPinScreen> {
  String? _first;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bc.bg,
      appBar: AppBar(backgroundColor: context.bc.bg),
      body: SafeArea(
        child: PinPad(
          key: ValueKey(_first == null),
          title: _first == null ? widget.title : 'Confirm your PIN',
          subtitle: _first == null ? widget.subtitle : 'Enter the same PIN again',
          error: _error,
          onDone: (pin) async {
            if (_first == null) {
              setState(() {
                _first = pin;
                _error = null;
              });
            } else if (pin == _first) {
              Navigator.pop(context, pin);
            } else {
              setState(() {
                _first = null;
                _error = "PINs didn't match. Try again.";
              });
            }
          },
        ),
      ),
    );
  }
}

/// App lock PIN (extra to fingerprint): kept only on this phone, as a salted hash.
class AppPin {
  static Future<String> _hash(String pin, String salt) async {
    final h = await Sha256().hash(utf8.encode('$salt:$pin'));
    return base64Encode(h.bytes);
  }

  static Future<bool> isSet() async => (await SharedPreferences.getInstance()).getString('app_pin') != null;

  static Future<void> set(String pin) async {
    final p = await SharedPreferences.getInstance();
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await p.setString('app_pin_salt', salt);
    await p.setString('app_pin', await _hash(pin, salt));
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('app_pin');
    await p.remove('app_pin_salt');
  }

  static Future<bool> check(String pin) async {
    final p = await SharedPreferences.getInstance();
    final h = p.getString('app_pin');
    if (h == null) return false;
    return await _hash(pin, p.getString('app_pin_salt') ?? '') == h;
  }
}
