import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

final _urlRe = RegExp(
  r'((?:https?:\/\/|www\.)[^\s<>"]+|\b[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*\.(?:com|in|org|net|io|dev|app|co|me|ai|gov|edu|info|xyz|tv|ly|gl|link)(?:\/[^\s<>"]*)?|[\w.+-]+@[\w-]+\.[\w.-]+|\+?\d[\d -]{8,}\d)',
  caseSensitive: false,
);

/// First web link in [text], ready to open (adds https:// if missing).
String? firstUrl(String text) {
  for (final m in _urlRe.allMatches(text)) {
    final s = _trimEnd(m.group(0)!);
    if (s.contains('@') && !s.contains('/')) continue; // email
    if (RegExp(r'^\+?[\d -]+$').hasMatch(s)) continue; // phone
    return s.toLowerCase().startsWith('http') ? s : 'https://$s';
  }
  return null;
}

String _trimEnd(String s) {
  while (s.isNotEmpty && '.,;:!?)]}\'"'.contains(s[s.length - 1])) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

Future<void> openLink(BuildContext context, String raw) async {
  final s = raw.trim();
  Uri uri;
  if (s.contains('@') && !s.contains('/') && !s.startsWith('http')) {
    uri = Uri(scheme: 'mailto', path: s);
  } else if (RegExp(r'^\+?[\d -]+$').hasMatch(s)) {
    uri = Uri(scheme: 'tel', path: s.replaceAll(' ', ''));
  } else {
    uri = Uri.parse(s.toLowerCase().startsWith('http') ? s : 'https://$s');
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open this link")));
  }
}

/// Message text with tappable links, emails and phone numbers.
/// Long-press a link to copy it.
class LinkText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  const LinkText(this.text, {super.key, required this.style, required this.linkColor});
  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final _recognizers = <GestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final t = widget.text;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _urlRe.allMatches(t)) {
      final link = _trimEnd(m.group(0)!);
      if (m.start > last) spans.add(TextSpan(text: t.substring(last, m.start)));
      final rec = TapGestureRecognizer()
        ..onTap = () {
          HapticFeedback.selectionClick();
          openLink(context, link);
        };
      _recognizers.add(rec);
      spans.add(TextSpan(
        text: link,
        recognizer: rec,
        style: TextStyle(color: widget.linkColor, decoration: TextDecoration.underline, decorationColor: widget.linkColor),
      ));
      last = m.start + link.length;
    }
    if (last < t.length) spans.add(TextSpan(text: t.substring(last)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}

/// Reads a page's title / description / image (Open Graph) on the sender's
/// phone. The preview travels inside the encrypted message, so the person
/// receiving it never contacts the website.
Future<Map<String, dynamic>?> fetchLinkPreview(String url) async {
  try {
    final r = await http.get(Uri.parse(url), headers: {
      'user-agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Mobile Safari/537.36 BAATLY',
      'accept': 'text/html',
    }).timeout(const Duration(seconds: 8));
    if (r.statusCode >= 400) return null;
    final ct = r.headers['content-type'] ?? '';
    if (!ct.contains('html')) return null;
    var html = utf8.decode(r.bodyBytes.length > 400000 ? r.bodyBytes.sublist(0, 400000) : r.bodyBytes, allowMalformed: true);
    final head = html.indexOf('</head>');
    if (head > 0) html = html.substring(0, head);
    String? meta(String name) {
      final re1 = RegExp('<meta[^>]+(?:property|name)=["\']$name["\'][^>]*content=["\']([^"\']*)["\']', caseSensitive: false);
      final re2 = RegExp('<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:property|name)=["\']$name["\']', caseSensitive: false);
      final m = re1.firstMatch(html) ?? re2.firstMatch(html);
      final v = m?.group(1)?.trim();
      return v == null || v.isEmpty ? null : _unescape(v);
    }

    final title = meta('og:title') ?? meta('twitter:title') ?? RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(html)?.group(1)?.trim();
    if (title == null || title.isEmpty) return null;
    final desc = meta('og:description') ?? meta('twitter:description') ?? meta('description');
    final site = meta('og:site_name') ?? Uri.parse(url).host.replaceFirst('www.', '');
    String? img = meta('og:image') ?? meta('twitter:image');
    String? thumb;
    if (img != null) {
      try {
        final iu = Uri.parse(url).resolve(img);
        final ir = await http.get(iu).timeout(const Duration(seconds: 8));
        if (ir.statusCode == 200 && ir.bodyBytes.length < 8 * 1024 * 1024) {
          final codec = await ui.instantiateImageCodec(ir.bodyBytes, targetWidth: 160);
          final frame = await codec.getNextFrame();
          final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
          if (png != null) {
            final b = base64Encode(png.buffer.asUint8List());
            if (b.length < 30000) thumb = b;
          }
        }
      } catch (_) {}
    }
    return {
      'u': url,
      'ti': _cut(_unescape(title), 140),
      if (desc != null) 'de': _cut(desc, 220),
      's': _cut(site, 60),
      if (thumb != null) 'im': thumb,
    };
  } catch (_) {
    return null;
  }
}

String _cut(String s, int n) => s.length <= n ? s : '${s.substring(0, n - 1)}…';

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ');

/// The preview card shown above the text (in the bubble) or above the composer.
class LinkPreviewCard extends StatelessWidget {
  final Map<String, dynamic> lp;
  final Color fg;
  final Color bg;
  final VoidCallback? onClose;
  const LinkPreviewCard({super.key, required this.lp, required this.fg, required this.bg, this.onClose});

  @override
  Widget build(BuildContext context) {
    final im = lp['im'] as String?;
    return GestureDetector(
      onTap: onClose != null ? null : () => openLink(context, lp['u'] as String),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (im != null)
            Image.memory(base64Decode(im), width: 78, height: 78, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => const SizedBox()),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lp['ti'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: fg)),
                if (lp['de'] != null) ...[
                  const SizedBox(height: 2),
                  Text(lp['de'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: fg.withOpacity(0.75))),
                ],
                const SizedBox(height: 3),
                Text(lp['s'] as String? ?? '', maxLines: 1, style: TextStyle(fontSize: 11, color: fg.withOpacity(0.6))),
              ]),
            ),
          ),
          if (onClose != null) IconButton(visualDensity: VisualDensity.compact, onPressed: onClose, icon: Icon(Icons.close_rounded, size: 18, color: fg.withOpacity(0.7))),
        ]),
      ),
    );
  }
}
