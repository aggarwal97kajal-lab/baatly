import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../data/app_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'pin_pad.dart';
import '../screens/settings/two_step.dart';

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
  bool _hasPin = false;
  bool _pinMode = false;
  String? _pinError;
  DateTime? _justUnlocked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) _startLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When a BAATLY PIN is set, the PIN pad opens straight away (fingerprint is one tap away).
  /// Without a PIN the fingerprint prompt opens on its own.
  Future<void> _startLock() async {
    final has = await AppPin.isSet();
    if (!mounted) return;
    setState(() {
      _hasPin = has;
      _pinMode = has;
      _pinError = null;
    });
    if (!has) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (!AppState.instance.appLock) return;
    // The fingerprint / screen-lock prompt itself pauses and resumes the app on many phones.
    // Those events must not lock again, or the prompt keeps coming back.
    if (_asking || _locked) return;
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _away ??= DateTime.now();
    } else if (s == AppLifecycleState.resumed) {
      final away = _away;
      _away = null;
      if (away == null) return;
      if (_justUnlocked != null && DateTime.now().difference(_justUnlocked!).inSeconds < 5) return;
      if (DateTime.now().difference(away).inSeconds >= 30) {
        setState(() => _locked = true);
        _startLock();
      }
    }
  }

  void _open() {
    if (!mounted) return;
    _justUnlocked = DateTime.now();
    _away = null;
    setState(() {
      _locked = false;
      _pinMode = false;
      _pinError = null;
    });
  }

  Future<void> _unlock() async {
    if (_asking) return;
    _asking = true;
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Unlock BAATLY',
        // stickyAuth restarts the prompt every time the app resumes, which loops on some phones.
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: false),
      );
      if (ok) _open();
    } catch (_) {
      // No lock set on the phone: fall back to the PIN if there is one, otherwise don't trap the user.
      if (_hasPin) {
        if (mounted) setState(() => _pinMode = true);
      } else {
        _open();
      }
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
              child: _pinMode
                  ? PinPad(
                      title: 'Enter BAATLY PIN',
                      error: _pinError,
                      extra: TextButton.icon(
                        onPressed: () {
                          setState(() => _pinMode = false);
                          _unlock();
                        },
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: const Text('Use fingerprint'),
                      ),
                      onDone: (pin) async {
                        if (await AppPin.check(pin)) {
                          _open();
                        } else if (mounted) {
                          setState(() => _pinError = 'Wrong PIN');
                        }
                      },
                    )
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const BaatlyMark(size: 72),
                      const SizedBox(height: 18),
                      Text('BAATLY is locked', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: context.bc.text)),
                      const SizedBox(height: 24),
                      FilledButton.icon(onPressed: _unlock, icon: const Icon(Icons.fingerprint_rounded), label: const Text('Unlock')),
                      if (_hasPin) ...[
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => setState(() {
                            _pinMode = true;
                            _pinError = null;
                          }),
                          child: const Text('Use PIN'),
                        ),
                      ],
                    ]),
            ),
          ),
        ),
    ]);
  }
}
