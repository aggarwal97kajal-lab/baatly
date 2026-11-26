import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../config.dart';
import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';
import '../chat/contact_actions.dart';

/// What a BAATLY QR code holds: baatly://u/<user id>
String myQrData() => 'baatly://u/${Messenger.instance.myId ?? ''}';

/// User id inside a scanned code, or null if it isn't a BAATLY code.
String? userIdFromQr(String? raw) {
  if (raw == null) return null;
  final u = Uri.tryParse(raw.trim());
  if (u == null) return null;
  if (u.scheme == 'baatly' && u.host == 'u' && u.pathSegments.isNotEmpty) return u.pathSegments.first;
  // Shared as a web link: https://…/u/<id>
  if ((u.scheme == 'https' || u.scheme == 'http') && u.pathSegments.length == 2 && u.pathSegments.first == 'u') return u.pathSegments[1];
  return null;
}

/// Found someone by QR / link: show their profile with Message + Add contact.
Future<void> openUserFromQr(BuildContext context, String id) async {
  if (id == Messenger.instance.myId) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This is your own QR code')));
    return;
  }
  final chat = await Messenger.instance.chatForUser(id);
  if (!context.mounted) return;
  if (chat == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't find this BAATLY account")));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sh) {
      final bc = sh.bc;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Avatar(initials: chat.initials, colorIndex: chat.colorIndex, photo: chat.photo, size: 76)),
            const SizedBox(height: 10),
            Text(chat.name, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: bc.text)),
            if (chat.about.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(chat.about, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: bc.muted)),
            ],
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                Navigator.pop(sh);
                AppState.instance.openChat(chat);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)));
              },
              child: const Text('Message'),
            ),
            if ((chat.phone ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () {
                  Navigator.pop(sh);
                  viewInAddressBook(context, chat);
                },
                child: const Text('Add contact'),
              ),
            ],
          ]),
        ),
      );
    },
  );
}

/// "QR code": My code | Scan code.
class QrScreen extends StatefulWidget {
  final bool scan;
  const QrScreen({super.key, this.scan = false});
  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.scan ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR code'),
        actions: [
          if (_tabs.index == 0)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => SharePlus.instance.share(ShareParams(text: 'Chat with me on BAATLY: $kApiBase/u/${Messenger.instance.myId ?? ''}')),
            ),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'My code'), Tab(text: 'Scan code')]),
      ),
      body: TabBarView(
        controller: _tabs,
        physics: const NeverScrollableScrollPhysics(),
        children: [const _MyCode(), _Scanner(active: _tabs.index == 1)],
      ),
    );
  }
}

class _MyCode extends StatelessWidget {
  const _MyCode();
  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final bc = context.bc;
    final name = s.name.isEmpty ? 'You' : s.name;
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    final ini = (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
    return ListView(padding: const EdgeInsets.fromLTRB(24, 48, 24, 24), children: [
      Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Container(
          margin: const EdgeInsets.only(top: 36),
          padding: const EdgeInsets.fromLTRB(18, 50, 18, 22),
          decoration: BoxDecoration(color: bc.surface, borderRadius: BorderRadius.circular(24)),
          child: Column(children: [
            Text(name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: bc.text)),
            Text('BAATLY contact', style: TextStyle(color: bc.muted)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: QrImageView(
                data: myQrData(),
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1A1410)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1A1410)),
              ),
            ),
          ]),
        ),
        Avatar(initials: ini, colorIndex: 2, size: 72, photo: s.myPhoto),
      ]),
      const SizedBox(height: 18),
      Text('Your QR code is private. If you share it with someone, they can scan it with BAATLY to add you.',
          textAlign: TextAlign.center, style: TextStyle(color: bc.muted, height: 1.4)),
    ]);
  }
}

class _Scanner extends StatefulWidget {
  final bool active;
  const _Scanner({required this.active});
  @override
  State<_Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<_Scanner> {
  final _ctrl = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _handling = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _found(String? raw) async {
    if (_handling) return;
    final id = userIdFromQr(raw);
    if (id == null) {
      if (raw != null && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This is not a BAATLY QR code')));
      }
      return;
    }
    _handling = true;
    try {
      await _ctrl.stop();
    } catch (_) {}
    if (mounted) await openUserFromQr(context, id);
    if (mounted) {
      try {
        await _ctrl.start();
      } catch (_) {}
    }
    _handling = false;
  }

  Future<void> _fromGallery() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f == null) return;
    final r = await _ctrl.analyzeImage(f.path);
    final raw = r?.barcodes.isNotEmpty == true ? r!.barcodes.first.rawValue : null;
    if (raw == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No QR code found in this photo')));
      return;
    }
    await _found(raw);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const ColoredBox(color: Colors.black);
    return Stack(fit: StackFit.expand, children: [
      MobileScanner(
        controller: _ctrl,
        onDetect: (cap) {
          final raw = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
          _found(raw);
        },
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Camera permission is needed to scan QR codes.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.9))),
          ),
        ),
      ),
      IgnorePointer(
        child: Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ),
      const Positioned(
        left: 0,
        right: 0,
        bottom: 120,
        child: Text('Scan a BAATLY QR code', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15)),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 30,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _round(Icons.photo_library_outlined, 'Gallery', _fromGallery),
          const SizedBox(width: 60),
          _round(Icons.flash_on_rounded, 'Flash', () => _ctrl.toggleTorch()),
        ]),
      ),
    ]);
  }

  Widget _round(IconData i, String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Color(0x55000000), shape: BoxShape.circle),
            child: Icon(i, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );
}
