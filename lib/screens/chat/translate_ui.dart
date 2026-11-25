import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/app_state.dart';
import '../../data/messenger.dart';
import '../../data/models.dart';
import '../../data/translate.dart';
import '../../theme/app_theme.dart';

/// Translation shown under a message.
class TranslationLine extends StatelessWidget {
  final Map<String, dynamic> tr;
  final Color fg;
  const TranslationLine({super.key, required this.tr, required this.fg});

  @override
  Widget build(BuildContext context) {
    final from = tr['from'] as String?;
    final to = tr['to'] as String?;
    final label = tr['label'] as String? ??
        (from != null && to != null ? '${Translate.instance.nameOf(from)} → ${Translate.instance.nameOf(to)}' : 'Translated');
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: fg.withOpacity(0.18)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text((tr['t'] as String?) ?? '', style: TextStyle(fontSize: 15, color: fg.withOpacity(0.92), height: 1.35)),
        const SizedBox(height: 3),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.translate_rounded, size: 12, color: fg.withOpacity(0.6)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: fg.withOpacity(0.6))),
        ]),
      ]),
    );
  }
}

Future<String?> pickLanguage(BuildContext context, {String? current, String title = 'Language'}) {
  final langs = Translate.instance.languages;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sh) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sh).size.height * 0.7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final (code, name) in langs)
                ListTile(
                  title: Text(name),
                  trailing: code == current ? Icon(Icons.check_rounded, color: sh.primary) : null,
                  onTap: () => Navigator.pop(sh, code),
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
}

Future<String> _defaultTarget() async {
  final p = await SharedPreferences.getInstance();
  return p.getString('tr_to') ?? 'hi';
}

Future<void> _rememberTarget(String code) async => (await SharedPreferences.getInstance()).setString('tr_to', code);

/// Long-press › Translate.
Future<void> translateMessage(BuildContext context, Chat chat, Message m) async {
  final to = await pickLanguage(context, current: chat.autoTranslate ?? await _defaultTarget(), title: 'Translate to');
  if (to == null || !context.mounted) return;
  await _rememberTarget(to);
  final snack = ScaffoldMessenger.of(context);
  snack.showSnackBar(const SnackBar(content: Text('Translating on this phone…'), duration: Duration(seconds: 2)));
  try {
    final r = await Translate.instance.run(m.text, to: to);
    if (r.from == to) {
      snack.showSnackBar(SnackBar(content: Text('Already in ${Translate.instance.nameOf(to)}')));
      return;
    }
    (m.media ??= {})['tr'] = {'to': to, 'from': r.from, 't': r.text};
    AppState.instance.changed();
  } catch (e) {
    snack.showSnackBar(SnackBar(content: Text(e is TranslateError ? e.message : "Couldn't translate")));
  }
}

/// Chat ⋮ › Translate: auto-translate their messages, translate what I send.
Future<void> translateSettings(BuildContext context, Chat chat) async {
  final def = await _defaultTarget();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sh) => StatefulBuilder(
      builder: (ctx, set) {
        final bc = ctx.bc;
        void changed() {
          set(() {});
          AppState.instance.changed();
        }

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 0, 22, 4),
              child: Align(alignment: Alignment.centerLeft, child: Text('Translate', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
              child: Text('Happens on this phone. Each language is a one-time ~30 MB download.', style: TextStyle(color: bc.muted, fontSize: 12.5)),
            ),
            SwitchListTile(
              title: Text('Auto-translate ${chat.name}\'s messages'),
              subtitle: Text(chat.autoTranslate == null ? 'Off' : 'Into ${Translate.instance.nameOf(chat.autoTranslate!)} · tap to change'),
              value: chat.autoTranslate != null,
              onChanged: (v) async {
                if (!v) {
                  chat.autoTranslate = null;
                  changed();
                  return;
                }
                final to = await pickLanguage(ctx, current: def, title: 'Show their messages in');
                if (to == null) return;
                chat.autoTranslate = to;
                await _rememberTarget(to);
                changed();
              },
            ),
            SwitchListTile(
              title: const Text('Translate what I send'),
              subtitle: Text(chat.sendTranslate == null ? 'Off · you write in your language, they get theirs' : 'Into ${Translate.instance.nameOf(chat.sendTranslate!)}'),
              value: chat.sendTranslate != null,
              onChanged: (v) async {
                if (!v) {
                  chat.sendTranslate = null;
                  changed();
                  return;
                }
                final to = await pickLanguage(ctx, title: 'Send my messages in');
                if (to == null) return;
                chat.sendTranslate = to;
                changed();
              },
            ),
            const SizedBox(height: 10),
          ]),
        );
      },
    ),
  );
}

/// "Transcribe" under a voice note → the words, worked out on this phone.
class TranscriptLine extends StatefulWidget {
  final Message m;
  final Color fg;
  final Color accent;
  const TranscriptLine({super.key, required this.m, required this.fg, required this.accent});

  @override
  State<TranscriptLine> createState() => _TranscriptLineState();
}

class _TranscriptLineState extends State<TranscriptLine> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('whisper_ok') != true) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Voice message transcripts'),
          content: const Text('BAATLY turns voice notes into text on this phone, so the audio never leaves it.\n\nThe first time, it downloads a speech model (about 140 MB). Use Wi-Fi if you can.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Not now')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Download')),
          ],
        ),
      );
      if (ok != true) return;
      await p.setBool('whisper_ok', true);
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final m = widget.m;
      var path = m.mediaPath;
      if (path == null || !File(path).existsSync()) path = await Messenger.instance.downloadMedia(m);
      if (path == null) throw TranslateError("Couldn't get the voice note");
      final text = await Transcriber.instance.run(path);
      (m.media ??= {})['tx'] = text;
      AppState.instance.changed();
    } catch (e) {
      if (mounted) setState(() => _error = e is TranslateError ? e.message : "Couldn't transcribe");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.m.media?['tx'] as String?;
    if (tx != null) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 260),
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: widget.fg.withOpacity(0.18)))),
        child: Text('"$tx"', style: TextStyle(fontSize: 14, color: widget.fg.withOpacity(0.92), height: 1.4)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: _busy
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: widget.accent)),
              const SizedBox(width: 8),
              Text('Transcribing…', style: TextStyle(fontSize: 12.5, color: widget.fg.withOpacity(0.75))),
            ])
          : GestureDetector(
              onTap: _go,
              child: Text(_error ?? 'Transcribe', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _error != null ? widget.fg.withOpacity(0.7) : widget.accent)),
            ),
    );
  }
}
