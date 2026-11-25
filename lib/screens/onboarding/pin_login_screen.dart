import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pin_pad.dart';

/// After the SMS code: the account's two-step PIN. Pops with the [AuthResult].
class PinLoginScreen extends StatefulWidget {
  final String ticket;
  final DateTime? resetAt;
  const PinLoginScreen({super.key, required this.ticket, this.resetAt});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen> {
  String? _error;
  bool _busy = false;
  late DateTime? _resetAt = widget.resetAt;

  String _date(DateTime t) => '${t.day}/${t.month}/${t.year}';

  Future<void> _check(String pin) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await Api.instance.verifyPin(widget.ticket, pin);
      if (mounted) Navigator.pop(context, r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't check. Check your connection.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Forgot PIN?'),
        content: const Text("For your safety, you can log in without the PIN only after 7 days. Your chats on this phone aren't affected."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Start 7-day wait')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final at = await Api.instance.forgotPin(widget.ticket);
      if (mounted) setState(() => _resetAt = at);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Scaffold(
      backgroundColor: bc.bg,
      appBar: AppBar(backgroundColor: bc.bg),
      body: SafeArea(
        child: PinPad(
          title: 'Two-step verification',
          subtitle: 'Enter the 6-digit PIN you created for this account.',
          error: _error,
          busy: _busy,
          extra: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _resetAt == null
                ? TextButton(onPressed: _forgot, child: const Text('Forgot PIN?'))
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Text("You can log in without the PIN after ${_date(_resetAt!)}. Verify your number again then.",
                        textAlign: TextAlign.center, style: TextStyle(color: bc.muted, fontSize: 13)),
                  ),
          ),
          onDone: _check,
        ),
      ),
    );
  }
}
