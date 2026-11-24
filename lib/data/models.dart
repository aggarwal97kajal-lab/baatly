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
  bool muted;
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
    this.muted = false,
    this.archived = false,
    this.unread = 0,
    List<Message>? messages,
  }) : messages = messages ?? [];

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

class StatusItem {
  final String name;
  final String initials;
  final int colorIndex;
  final String when;
  final List<String> texts;
  final List<int> bg;
  bool seen;
  StatusItem(this.name, this.initials, this.colorIndex, this.when, this.texts, this.bg, {this.seen = false});
}
