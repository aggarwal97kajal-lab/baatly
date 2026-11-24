import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'permissions_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _about = TextEditingController(text: 'Baat karte hain!');

  bool get _userOk => RegExp(r'^[a-z0-9._]{3,20}$').hasMatch(_user.text);

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    _about.dispose();
    super.dispose();
  }

  String get _initials {
    final parts = _name.text.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final ready = _name.text.trim().isNotEmpty && _userOk;
    return Scaffold(
      backgroundColor: bc.bg,
      appBar: AppBar(backgroundColor: bc.bg, title: const Text('Profile banayein'), centerTitle: true, automaticallyImplyLeading: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            const SizedBox(height: 12),
            Center(
              child: GestureDetector(
                onTap: () => showComingSoon(context, 'Photo lagana'),
                child: Stack(clipBehavior: Clip.none, children: [
                  AnimatedSwitcher(
                    duration: Mitti.fast,
                    child: _initials.isEmpty
                        ? Container(
                            key: const ValueKey('empty'),
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(color: bc.raised, shape: BoxShape.circle),
                            child: Icon(Icons.person_rounded, size: 64, color: bc.muted.withOpacity(0.5)),
                          )
                        : Avatar(key: ValueKey(_initials), initials: _initials, colorIndex: 2, size: 120),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: context.primary, shape: BoxShape.circle, border: Border.all(color: bc.bg, width: 4)),
                      child: const Icon(Icons.photo_camera_rounded, size: 17, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 28),
            _Field(label: 'Naam', ctrl: _name, hint: 'Aapka naam', onChanged: () => setState(() {}), helper: 'Ye naam aapke contacts ko dikhega.'),
            _Field(
              label: 'Username',
              ctrl: _user,
              hint: 'aarav.mehta',
              prefix: '@',
              onChanged: () => setState(() {}),
              helper: _user.text.isEmpty
                  ? '3-20 akshar: a-z, 0-9, . aur _'
                  : (_userOk ? '@${_user.text} available hai' : 'Sirf a-z, 0-9, . aur _ (3-20 akshar)'),
              helperColor: _user.text.isEmpty ? null : (_userOk ? Mitti.success : Mitti.error),
              trailing: _userOk ? const Icon(Icons.check_circle_rounded, color: Mitti.success) : null,
            ),
            _Field(label: 'About', ctrl: _about, hint: 'Kuch apne baare mein', onChanged: () => setState(() {}), maxLength: 140),
            const SizedBox(height: 20),
            AnimatedOpacity(
              opacity: ready ? 1 : 0.45,
              duration: Mitti.fast,
              child: FilledButton(
                onPressed: ready
                    ? () {
                        AppState.instance.finishOnboarding(name: _name.text, username: _user.text, about: _about.text);
                        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PermissionsScreen()));
                      }
                    : null,
                child: const Text('Ho gaya'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String hint;
  final String? prefix;
  final String? helper;
  final Color? helperColor;
  final Widget? trailing;
  final VoidCallback onChanged;
  final int? maxLength;
  const _Field({
    required this.label,
    required this.ctrl,
    required this.hint,
    required this.onChanged,
    this.prefix,
    this.helper,
    this.helperColor,
    this.trailing,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: bc.muted)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLength: maxLength,
          onChanged: (_) => onChanged(),
          style: TextStyle(fontSize: 15.5, color: bc.text),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            suffixIcon: trailing,
            filled: true,
            fillColor: bc.surface,
            counterText: maxLength == null ? null : '',
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: bc.line, width: 1.5)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: context.primary, width: 2)),
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(helper!, style: TextStyle(fontSize: 12, color: helperColor ?? bc.muted, fontWeight: FontWeight.w500)),
          ),
      ]),
    );
  }
}
