enum MsgStatus { sending, sent, delivered, read }

/// Saved by index: only ever append new kinds.
enum MsgKind { text, voice, image, doc, system, poll, location, contact, event, video, call }

class Message {
  final String id;
  String text;
  final bool fromMe;
  final DateTime time;
  MsgStatus status;
  MsgKind kind;
  /// Groups: who sent it (BAATLY user id).
  String? from;
  /// Deleted for everyone.
  bool deleted = false;
  /// View once: already opened.
  bool opened = false;
  /// Groups: members who received / read my message.
  final Set<String> deliveredBy = {};
  final Set<String> readBy = {};
  /// Message info: when it was delivered / read ('d', 'r' for 1:1; 'd:<uid>', 'r:<uid>' in groups), ms.
  final Map<String, int> receiptAt = {};
  final int voiceSeconds;
  String? reaction;
  /// Real chats: we already told the sender this message was read.
  bool readSent;
  /// Disappearing messages: deleted from this phone after this time.
  DateTime? expiresAt;
  bool starred;
  /// Media (photo / voice / document): file on this phone, once available.
  String? mediaPath;
  /// Media details sent inside the encrypted message (id, key, name, size, thumb…).
  Map<String, dynamic>? media;
  /// Upload/download in progress (not saved).
  bool busy = false;
  /// 0..1 while uploading/downloading, null when unknown.
  double? progress;

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
    this.starred = false,
    this.mediaPath,
    this.media,
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
        if (starred) 'st': true,
        if (kind != MsgKind.text) 'k': kind.index,
        if (voiceSeconds > 0) 'vs': voiceSeconds,
        if (mediaPath != null) 'mp': mediaPath,
        if (media != null) 'md': media,
        if (from != null) 'f': from,
        if (deleted) 'dl': true,
        if (opened) 'op': true,
        if (deliveredBy.isNotEmpty) 'db': deliveredBy.toList(),
        if (readBy.isNotEmpty) 'rb': readBy.toList(),
        if (receiptAt.isNotEmpty) 'ra': receiptAt,
      };

  factory Message.fromJson(Map<String, dynamic> j) => _fromJson(j)
    ..from = j['f'] as String?
    ..deleted = j['dl'] == true
    ..opened = j['op'] == true
    ..deliveredBy.addAll([for (final x in (j['db'] as List? ?? [])) x.toString()])
    ..readBy.addAll([for (final x in (j['rb'] as List? ?? [])) x.toString()])
    ..receiptAt.addAll({for (final e in ((j['ra'] as Map?) ?? {}).entries) e.key.toString(): (e.value as num).toInt()});

  static Message _fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        text: j['t'] as String? ?? '',
        fromMe: j['me'] == true,
        time: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
        status: MsgStatus.values[((j['s'] as int?) ?? 3).clamp(0, MsgStatus.values.length - 1)],
        reaction: j['r'] as String?,
        readSent: j['rs'] == true,
        expiresAt: j['x'] is int ? DateTime.fromMillisecondsSinceEpoch(j['x'] as int) : null,
        starred: j['st'] == true,
        kind: MsgKind.values[((j['k'] as int?) ?? 0).clamp(0, MsgKind.values.length - 1)],
        voiceSeconds: (j['vs'] as int?) ?? 0,
        mediaPath: j['mp'] as String?,
        media: (j['md'] as Map?)?.cast<String, dynamic>(),
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
  /// Real group chats: server group id, members and admins.
  final String? groupId;
  List<String> members = [];
  Set<String> admins = {};
  /// I'm no longer in this group.
  bool left = false;
  /// Groups: who is typing right now.
  String? typingName;
  /// Groups: icon version we have.
  int photoVer = 0;
  /// Groups: description and settings ('all' | 'admins').
  String description = '';
  String editInfo = 'admins';
  String sendMessages = 'all';
  /// Pinned message (any chat).
  String? pinnedId;
  /// Hidden behind fingerprint in "Locked chats".
  bool locked = false;
  /// In "Favourites" (chats filter + quick calls).
  bool favourite = false;
  /// Own colour / wallpaper for just this chat (null = app theme).
  int? themePalette;
  int? themeWallpaper;
  /// My chat lists ("Family", "Office"…) this chat is in.
  Set<String> lists = {};
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
    this.groupId,
    List<Message>? messages,
  })  : messages = messages ?? [],
        mutedUntil = muted ? DateTime(9999) : null;

  bool get muted => mutedUntil != null && DateTime.now().isBefore(mutedUntil!);
  bool get mutedForever => mutedUntil != null && mutedUntil!.year >= 9999;

  Message? get last => messages.isEmpty ? null : messages.last;

  bool get isReal => peerId != null || groupId != null;
  /// "Notes (You)": private chat with yourself, never leaves this phone (except your backup).
  bool get isNotes => id == 'notes';
  bool get isRealGroup => groupId != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'initials': initials,
        'color': colorIndex,
        'about': about,
        'peer': peerId,
        'phone': phone,
        if (groupId != null) 'gid': groupId,
        if (isGroup) 'group': true,
        if (members.isNotEmpty) 'mem': members,
        if (admins.isNotEmpty) 'adm': admins.toList(),
        if (left) 'left': true,
        if (photoVer > 0) 'pv': photoVer,
        if (description.isNotEmpty) 'desc': description,
        'ei': editInfo,
        'sm': sendMessages,
        if (pinnedId != null) 'pin': pinnedId,
        if (favourite) 'fav': true,
        if (themePalette != null) 'tp': themePalette,
        if (themeWallpaper != null) 'tw': themeWallpaper,
        if (lists.isNotEmpty) 'ls': lists.toList(),
        if (locked) 'lk': true,
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
      groupId: j['gid'] as String?,
      isGroup: j['group'] == true,
      pinned: j['pinned'] == true,
      archived: j['archived'] == true,
      unread: j['unread'] as int? ?? 0,
      messages: [for (final m in (j['msgs'] as List? ?? [])) Message.fromJson(m as Map<String, dynamic>)],
    );
    c.photo = j['photo'] as String?;
    c.members = [for (final x in (j['mem'] as List? ?? [])) x.toString()];
    c.admins = {for (final x in (j['adm'] as List? ?? [])) x.toString()};
    c.left = j['left'] == true;
    c.photoVer = (j['pv'] as int?) ?? 0;
    c.description = j['desc'] as String? ?? '';
    c.editInfo = j['ei'] as String? ?? 'admins';
    c.sendMessages = j['sm'] as String? ?? 'all';
    c.pinnedId = j['pin'] as String?;
    c.locked = j['lk'] == true;
    c.themePalette = j['tp'] as int?;
    c.themeWallpaper = j['tw'] as int?;
    c.lists = {for (final x in (j['ls'] as List? ?? [])) x.toString()};
    c.favourite = j['fav'] == true;
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
  /// Real calls: who, so you can call back.
  final String? peerId;
  final DateTime? at;
  /// Server call id (to avoid logging the same call twice).
  final String? callId;
  CallLog(this.name, this.initials, this.colorIndex, this.kind, this.video, this.when, {this.peerId, this.at, this.callId});

  Map<String, dynamic> toJson() => {
        'n': name,
        'i': initials,
        'c': colorIndex,
        'k': kind.index,
        'v': video,
        'w': when,
        if (peerId != null) 'p': peerId,
        if (at != null) 'a': at!.millisecondsSinceEpoch,
        if (callId != null) 'id': callId,
      };
  factory CallLog.fromJson(Map<String, dynamic> j) => CallLog(
        j['n'] as String? ?? '',
        j['i'] as String? ?? '#',
        j['c'] as int? ?? 0,
        CallKind.values[((j['k'] as int?) ?? 0).clamp(0, CallKind.values.length - 1)],
        j['v'] == true,
        j['w'] as String? ?? '',
        peerId: j['p'] as String?,
        at: j['a'] is int ? DateTime.fromMillisecondsSinceEpoch(j['a'] as int) : null,
        callId: j['id'] as String?,
      );
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
  /// Song / audio clip on the status: {start, dur (ms), name, id?, k?}.
  Map<String, dynamic>? audio;
  String? audioPath;
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
