enum MsgStatus { sending, sent, delivered, read }

enum MsgKind { text, voice }

class Message {
  final String id;
  final String text;
  final bool fromMe;
  final DateTime time;
  MsgStatus status;
  final MsgKind kind;
  final int voiceSeconds;
  String? reaction;

  Message({
    required this.id,
    required this.text,
    required this.fromMe,
    required this.time,
    this.status = MsgStatus.read,
    this.kind = MsgKind.text,
    this.voiceSeconds = 0,
    this.reaction,
  });
}

class Chat {
  final String id;
  final String name;
  final String initials;
  final int colorIndex;
  final bool isGroup;
  final String about;
  bool online;
  bool pinned;
  DateTime? mutedUntil; // null = not muted; year 9999 = always
  bool archived;
  bool typing = false;
  int unread;
  final List<Message> messages;

  Chat({
    required this.id,
    required this.name,
    required this.initials,
    required this.colorIndex,
    this.isGroup = false,
    this.about = '',
    this.online = false,
    this.pinned = false,
    bool muted = false,
    this.archived = false,
    this.unread = 0,
    List<Message>? messages,
  })  : messages = messages ?? [],
        mutedUntil = muted ? DateTime(9999) : null;

  bool get muted => mutedUntil != null && DateTime.now().isBefore(mutedUntil!);
  bool get mutedForever => mutedUntil != null && mutedUntil!.year >= 9999;

  Message? get last => messages.isEmpty ? null : messages.last;
}

enum CallKind { incoming, outgoing, missed }

class CallLog {
  final String name;
  final String initials;
  final int colorIndex;
  final CallKind kind;
  final bool video;
  final String when;
  CallLog(this.name, this.initials, this.colorIndex, this.kind, this.video, this.when);
}

/// One page of a status: either text on a colour, or a photo with caption.
class StatusSlide {
  final String? text;
  final String? imagePath;
  final String? caption;
  final int bg;
  final DateTime at;
  StatusSlide.text(this.text, this.bg, {DateTime? at})
      : imagePath = null,
        caption = null,
        at = at ?? DateTime.now();
  StatusSlide.photo(this.imagePath, {this.caption, DateTime? at})
      : text = null,
        bg = 0xFF000000,
        at = at ?? DateTime.now();
  bool get isPhoto => imagePath != null;
}

class StatusItem {
  final String name;
  final String initials;
  final int colorIndex;
  final String when;
  final List<StatusSlide> slides;
  bool seen;
  StatusItem(this.name, this.initials, this.colorIndex, this.when, this.slides, {this.seen = false});
}
