import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// On-phone translation (Google ML Kit). Text never leaves the phone.
class Translate {
  Translate._();
  static final instance = Translate._();

  static const _names = {
    'af': 'Afrikaans', 'ar': 'Arabic', 'be': 'Belarusian', 'bg': 'Bulgarian', 'bn': 'Bengali', 'ca': 'Catalan', 'cs': 'Czech',
    'cy': 'Welsh', 'da': 'Danish', 'de': 'German', 'el': 'Greek', 'en': 'English', 'eo': 'Esperanto', 'es': 'Spanish',
    'et': 'Estonian', 'fa': 'Persian', 'fi': 'Finnish', 'fr': 'French', 'ga': 'Irish', 'gl': 'Galician', 'gu': 'Gujarati',
    'he': 'Hebrew', 'hi': 'Hindi', 'hr': 'Croatian', 'ht': 'Haitian', 'hu': 'Hungarian', 'id': 'Indonesian', 'is': 'Icelandic',
    'it': 'Italian', 'ja': 'Japanese', 'ka': 'Georgian', 'kn': 'Kannada', 'ko': 'Korean', 'lt': 'Lithuanian', 'lv': 'Latvian',
    'mk': 'Macedonian', 'mr': 'Marathi', 'ms': 'Malay', 'mt': 'Maltese', 'nl': 'Dutch', 'no': 'Norwegian', 'pl': 'Polish',
    'pt': 'Portuguese', 'ro': 'Romanian', 'ru': 'Russian', 'sk': 'Slovak', 'sl': 'Slovenian', 'sq': 'Albanian', 'sv': 'Swedish',
    'sw': 'Swahili', 'ta': 'Tamil', 'te': 'Telugu', 'th': 'Thai', 'tl': 'Tagalog', 'tr': 'Turkish', 'uk': 'Ukrainian',
    'ur': 'Urdu', 'vi': 'Vietnamese', 'zh': 'Chinese',
  };

  /// Languages this phone can translate, sorted by name: (code, name).
  List<(String, String)> get languages {
    final out = <(String, String)>[
      for (final l in TranslateLanguage.values) (l.bcpCode, _names[l.bcpCode] ?? l.name),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return out;
  }

  String nameOf(String code) => _names[code] ?? code;

  TranslateLanguage? _lang(String code) {
    for (final l in TranslateLanguage.values) {
      if (l.bcpCode == code) return l;
    }
    return null;
  }

  bool supported(String code) => _lang(code) != null;

  final _models = OnDeviceTranslatorModelManager();
  final Map<String, OnDeviceTranslator> _cache = {};

  Future<bool> hasModel(String code) => _models.isModelDownloaded(code);
  Future<bool> download(String code) => _models.downloadModel(code);

  /// Language code of [text] ('und' if unsure). Romanised Hindi comes back as 'hi-Latn'.
  Future<String> detect(String text) async {
    final id = LanguageIdentifier(confidenceThreshold: 0.45);
    try {
      return await id.identifyLanguage(text);
    } finally {
      id.close();
    }
  }

  /// Translates [text] into [to]. [from] is detected when null.
  /// Throws [TranslateError] with a message the user can read.
  Future<({String text, String from})> run(String text, {String? from, required String to}) async {
    var src = from ?? await detect(text);
    if (src == 'hi-Latn') throw TranslateError('This looks like Hinglish (Hindi in English letters). It can only be translated when written in Hindi script.');
    if (src == 'und') throw TranslateError("Couldn't tell which language this is");
    src = src.split('-').first;
    if (src == to) return (text: text, from: src);
    final a = _lang(src), b = _lang(to);
    if (a == null) throw TranslateError("${nameOf(src)} can't be translated on the phone yet");
    if (b == null) throw TranslateError("${nameOf(to)} can't be translated on the phone yet");
    for (final c in {src, to}) {
      if (!await _models.isModelDownloaded(c)) {
        final ok = await _models.downloadModel(c);
        if (!ok) throw TranslateError("Couldn't download ${nameOf(c)} (about 30 MB). Check your connection.");
      }
    }
    final key = '$src>$to';
    final t = _cache[key] ??= OnDeviceTranslator(sourceLanguage: a, targetLanguage: b);
    return (text: await t.translateText(text), from: src);
  }
}

class TranslateError implements Exception {
  final String message;
  TranslateError(this.message);
  @override
  String toString() => message;
}

/// Voice note → text on this phone (whisper.cpp). First use downloads the model (~140 MB).
class Transcriber {
  Transcriber._();
  static final instance = Transcriber._();
  final _ctrl = WhisperController();
  bool busy = false;

  Future<String> run(String audioPath) async {
    busy = true;
    try {
      final r = await _ctrl.transcribe(model: WhisperModel.base, audioPath: audioPath, lang: 'auto');
      final t = r?.transcription.text.trim() ?? '';
      if (t.isEmpty) throw TranslateError("Couldn't make out any words");
      return t;
    } finally {
      busy = false;
    }
  }
}
