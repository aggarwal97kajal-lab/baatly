import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';

const _tiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _ua = 'app.baatly.baatly';

TileLayer _tileLayer() => TileLayer(urlTemplate: _tiles, userAgentPackageName: _ua, maxZoom: 19);

Widget _attribution() => Positioned(
      right: 4,
      bottom: 2,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        color: Colors.white70,
        child: const Text('© OpenStreetMap', style: TextStyle(fontSize: 9, color: Colors.black87)),
      ),
    );

Marker _pin(LatLng p, {bool live = false}) => Marker(
      point: p,
      width: 44,
      height: 44,
      alignment: Alignment.topCenter,
      child: Icon(live ? Icons.share_location_rounded : Icons.location_on_rounded, color: live ? const Color(0xFF2E7D5B) : const Color(0xFFC8553D), size: 44),
    );

/// "Send location" like WhatsApp: map, live location, current location, or a pinned spot.
class SendLocationScreen extends StatefulWidget {
  const SendLocationScreen({super.key});
  @override
  State<SendLocationScreen> createState() => _SendLocationScreenState();
}

class _SendLocationScreenState extends State<SendLocationScreen> {
  final _map = MapController();
  Position? _pos;
  LatLng? _center;
  bool _moved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() => _error = null);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _error = 'Turn on location (GPS) to share where you are.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _error = 'Allow location for BAATLY to share it.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      setState(() {
        _pos = p;
        _center = LatLng(p.latitude, p.longitude);
        _moved = false;
      });
      _map.move(LatLng(p.latitude, p.longitude), 16);
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't get your location ($e)");
    }
  }

  Future<void> _live() async {
    final mins = await showDialog<int>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Share live location for'),
        children: [
          for (final (m, l) in const [(15, '15 minutes'), (60, '1 hour'), (480, '8 hours')])
            SimpleDialogOption(onPressed: () => Navigator.pop(d, m), child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(l))),
        ],
      ),
    );
    if (mins == null || _pos == null || !mounted) return;
    Navigator.pop(context, {
      'type': 'location',
      'live': true,
      'lat': _pos!.latitude,
      'lng': _pos!.longitude,
      'until': DateTime.now().add(Duration(minutes: mins)).millisecondsSinceEpoch,
      'upd': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bc = context.bc;
    final me = _pos == null ? null : LatLng(_pos!.latitude, _pos!.longitude);
    return Scaffold(
      appBar: AppBar(title: const Text('Send location'), actions: [IconButton(onPressed: _locate, icon: const Icon(Icons.refresh_rounded))]),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: me ?? const LatLng(28.6139, 77.2090),
                initialZoom: me == null ? 11 : 16,
                onPositionChanged: (cam, hasGesture) {
                  if (hasGesture) setState(() {
                    _center = cam.center;
                    _moved = true;
                  });
                },
              ),
              children: [
                _tileLayer(),
                if (me != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: me,
                      width: 22,
                      height: 22,
                      child: Container(decoration: BoxDecoration(color: const Color(0xFF3D7DC8), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3))),
                    ),
                  ]),
              ],
            ),
            if (_moved) const IgnorePointer(child: Center(child: Padding(padding: EdgeInsets.only(bottom: 40), child: Icon(Icons.location_on_rounded, color: Color(0xFFC8553D), size: 44)))),
            _attribution(),
            Positioned(
              right: 12,
              top: 12,
              child: FloatingActionButton.small(heroTag: 'me', onPressed: _locate, child: const Icon(Icons.my_location_rounded)),
            ),
          ]),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: bc.muted))),
        ListTile(
          enabled: _pos != null,
          leading: const CircleAvatar(backgroundColor: Color(0xFF2E7D5B), child: Icon(Icons.share_location_rounded, color: Colors.white)),
          title: const Text('Share live location', style: TextStyle(fontWeight: FontWeight.w600)),
          onTap: _live,
        ),
        ListTile(
          enabled: _pos != null,
          leading: const CircleAvatar(backgroundColor: Color(0xFFC8553D), child: Icon(Icons.my_location_rounded, color: Colors.white)),
          title: const Text('Send your current location', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(_pos == null ? 'Finding you…' : 'Accurate to ${_pos!.accuracy.round()} meters'),
          onTap: () => Navigator.pop(context, {'type': 'location', 'lat': _pos!.latitude, 'lng': _pos!.longitude}),
        ),
        if (_moved && _center != null)
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.place_outlined)),
            title: const Text('Send this pinned location', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${_center!.latitude.toStringAsFixed(5)}, ${_center!.longitude.toStringAsFixed(5)}'),
            onTap: () => Navigator.pop(context, {'type': 'location', 'lat': _center!.latitude, 'lng': _center!.longitude}),
          ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

/// Location in a chat bubble: small map; live ones keep moving.
class LocationContent extends StatelessWidget {
  final Chat chat;
  final Message m;
  final Color fg;
  const LocationContent({super.key, required this.chat, required this.m, required this.fg});

  @override
  Widget build(BuildContext context) {
    final md = m.media ?? {};
    final p = LatLng((md['lat'] as num?)?.toDouble() ?? 0, (md['lng'] as num?)?.toDouble() ?? 0);
    final live = md['live'] == true;
    final until = DateTime.fromMillisecondsSinceEpoch((md['until'] as int?) ?? 0);
    final active = live && md['stopped'] != true && until.isAfter(DateTime.now());
    final w = MediaQuery.of(context).size.width * 0.64;
    String hm(DateTime t) => '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    return SizedBox(
      width: w,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LocationViewScreen(m: m, title: chat.name))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 150,
              child: AbsorbPointer(
                child: Stack(children: [
                  FlutterMap(
                    key: ValueKey('${p.latitude},${p.longitude}'),
                    options: MapOptions(initialCenter: p, initialZoom: 15, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
                    children: [_tileLayer(), MarkerLayer(markers: [_pin(p, live: active)])],
                  ),
                  _attribution(),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Icon(live ? Icons.share_location_rounded : Icons.location_on_rounded, size: 18, color: fg),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              live ? (active ? 'Live until ${hm(until)}' : 'Live location ended') : 'Location',
              style: TextStyle(fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ]),
        if (live && active && m.fromMe)
          TextButton(
            onPressed: () => Messenger.instance.stopLive(chat, m),
            child: Text('Stop sharing', style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}

/// Full map for a shared location (follows live updates).
class LocationViewScreen extends StatelessWidget {
  final Message m;
  final String title;
  const LocationViewScreen({super.key, required this.m, required this.title});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final md = m.media ?? {};
        final p = LatLng((md['lat'] as num?)?.toDouble() ?? 0, (md['lng'] as num?)?.toDouble() ?? 0);
        final upd = md['upd'] is int ? DateTime.fromMillisecondsSinceEpoch(md['upd'] as int) : null;
        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Stack(children: [
            FlutterMap(
              key: ValueKey('${p.latitude},${p.longitude}'),
              options: MapOptions(initialCenter: p, initialZoom: 16),
              children: [_tileLayer(), MarkerLayer(markers: [_pin(p, live: md['live'] == true)])],
            ),
            _attribution(),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Column(children: [
                if (md['live'] == true && upd != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                    child: Text('Updated ${DateTime.now().difference(upd).inMinutes} min ago', style: const TextStyle(color: Colors.white)),
                  ),
                FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${p.latitude},${p.longitude}'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.directions_rounded),
                  label: const Text('Open in Google Maps'),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
