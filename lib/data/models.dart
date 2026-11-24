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
  /// Real chats: we already told the sender this message was read.
  bool readSent;
  /// Disappearing messages: deleted from this phone after this time.
  DateTime? expiresAt;

  Message({
    required this.id,
    required this.text,
    required this.fromMe,
    required this.time,
    this.status = MsgStatus.read,
    this.kind = MsgKind.text,
    this.voiceSeconds = 0,
    this.reaction,
    this.readSent = false,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        't': text,
        'me': fromMe,
        'at': time.millisecondsSinceEpoch,
        's': status.index,
        if (reaction != null) 'r': reaction,
        if (readSent) 'rs': true,
        if (expiresAt != null) 'x': expiresAt!.millisecondsSinceEpoch,
      };

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        text: j['t'] as String? ?? '',
        fromMe: j['me'] == true,
        time: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
        status: MsgStatus.values[((j['s'] as int?) ?? 3).clamp(0, MsgStatus.values.length - 1)],
        reaction: j['r'] as String?,
        readSent: j['rs'] == true,
        expiresAt: j['x'] is int ? DateTime.fromMillisecondsSinceEpoch(j['x'] as int) : null,
      );
}

class Chat {
  final String id;
  String name;
  String initials;
  final int colorIndex;
  final bool isGroup;
  String about;
  /// Real chats only: the other person's BAATLY user id and phone.
  final String? peerId;
  String? phone;
  /// Real chats only: "online" / "last seen …" from the server.
  String? presence;
  /// Profile photo file on this phone (real chats).
  String? photo;
  /// Disappearing messages timer for this chat, seconds (0 = off).
  int disappear = 0;
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
    this.peerId,
    this.phone,
    List<Message>? messages,
  })  : messages = messages ?? [],
        mutedUntil = muted ? DateTime(9999) : null;

  bool get muted => mutedUntil != null && DateTime.now().isBefore(mutedUntil!);
  bool get mutedForever => mutedUntil != null && mutedUntil!.year >= 9999;

  Message? get last => messages.isEmpty ? null : messages.last;

  bool get isReal => peerId != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'initials': initials,
        'color': colorIndex,
        'about': about,
        'peer': peerId,
        'phone': phone,
        'pinned': pinned,
        'archived': archived,
        'unread': unread,
        if (photo != null) 'photo': photo,
        if (disappear > 0) 'dis': disappear,
        if (mutedUntil != null) 'mute': mutedUntil!.millisecondsSinceEpoch,
        'msgs': messages.map((m) => m.toJson()).toList(),
      };

  factory Chat.fromJson(Map<String, dynamic> j) {
    final c = Chat(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      initials: j['initials'] as String? ?? '?',
      colorIndex: j['color'] as int? ?? 0,
      about: j['about'] as String? ?? '',
      peerId: j['peer'] as String?,
      phone: j['phone'] as String?,
      pinned: j['pinned'] == true,
      archived: j['archived'] == true,
      unread: j['unread'] as int? ?? 0,
      messages: [for (final m in (j['msgs'] as List? ?? [])) Message.fromJson(m as Map<String, dynamic>)],
    );
    c.photo = j['photo'] as String?;
    c.disappear = (j['dis'] as int?) ?? 0;
    final mute = j['mute'] as int?;
    if (mute != null) c.mutedUntil = DateTime.fromMillisecondsSinceEpoch(mute);
    return c;
  }
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

  /// Server id once uploaded (real statuses).
  String? remoteId;
  bool uploading = false;
  bool failed = false;
  int views = 0;
  bool seen = false;
  /// Own updates: who viewed it (user id -> time, ms).
  final Map<String, int> viewerAt = {};
  int get viewCount => viewerAt.length > views ? viewerAt.length : views;

  StatusSlide.text(this.text, this.bg, {DateTime? at, this.remoteId})
      : imagePath = null,
        caption = null,
        at = at ?? DateTime.now();
  StatusSlide.photo(this.imagePath, {this.caption, DateTime? at, this.remoteId})
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
  /// Real statuses: the owner's BAATLY id.
  final String? ownerId;
  StatusItem(this.name, this.initials, this.colorIndex, this.when, this.slides, {this.seen = false, this.ownerId});
}
