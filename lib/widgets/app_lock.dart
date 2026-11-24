import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../data/app_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Covers the app until fingerprint / screen lock succeeds (when App lock is on).
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});
  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = AppState.instance.appLock;
  bool _asking = false;
  DateTime? _away;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (!AppState.instance.appLock) return;
    if (s == AppLifecycleState.paused) _away = DateTime.now();
    if (s == AppLifecycleState.resumed && _away != null && DateTime.now().difference(_away!).inSeconds > 30 && !_asking) {
      setState(() => _locked = true);
      _unlock();
    }
  }

  Future<void> _unlock() async {
    if (_asking) return;
    _asking = true;
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Unlock BAATLY',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (ok && mounted) setState(() => _locked = false);
    } catch (_) {
      // No lock set on the phone: don't trap the user.
      if (mounted) setState(() => _locked = false);
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (_locked)
        Positioned.fill(
          child: Material(
            color: context.bc.bg,
            child: SafeArea(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const BaatlyMark(size: 72),
                const SizedBox(height: 18),
                Text('BAATLY is locked', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.bc.text)),
                const SizedBox(height: 24),
                FilledButton.icon(onPressed: _unlock, icon: const Icon(Icons.fingerprint_rounded), label: const Text('Unlock')),
              ]),
            ),
          ),
        ),
    ]);
  }
}
