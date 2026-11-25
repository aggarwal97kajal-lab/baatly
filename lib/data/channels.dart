import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

class Channel {
  final String id;
  String name;
  String description;
  int followers;
  DateTime? lastPost;
  String lastText;
  bool mine;
  bool following;
  Channel.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? '',
        description = j['description'] as String? ?? '',
        followers = (j['followers'] as num?)?.toInt() ?? 0,
        lastPost = (j['lastPost'] as num?) == null || (j['lastPost'] as num) == 0 ? null : DateTime.fromMillisecondsSinceEpoch((j['lastPost'] as num).toInt()),
        lastText = j['lastText'] as String? ?? '',
        mine = j['mine'] == true,
        following = j['following'] == true;
}

class ChannelPost {
  final String id;
  final String text;
  final Map<String, dynamic>? media;
  final DateTime at;
  List<({String e, int n, bool mine})> reactions;
  ChannelPost.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        text = j['text'] as String? ?? '',
        media = (j['media'] as Map?)?.cast<String, dynamic>(),
        at = DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
        reactions = [
          for (final r in (j['reactions'] as List? ?? []))
            (e: (r as Map)['e'] as String, n: (r['n'] as num).toInt(), mine: r['mine'] == true),
        ];
}

/// Channels I follow / own. Posts are public (not end-to-end encrypted), like WhatsApp channels.
class ChannelService extends ChangeNotifier {
  ChannelService._();
  static final instance = ChannelService._();

  List<Channel> mine = [];
  final Map<String, int> _seen = {};
  bool loaded = false;

  int unread(Channel c) {
    final lp = c.lastPost?.millisecondsSinceEpoch ?? 0;
    return lp > (_seen[c.id] ?? 0) && !c.mine ? 1 : 0;
  }

  Future<void> refresh() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys().where((k) => k.startsWith('ch_seen_'))) {
        _seen[k.substring(8)] = p.getInt(k) ?? 0;
      }
      final d = await Api.instance.request('GET', '/v1/channels/mine');
      mine = [for (final x in (d['channels'] as List? ?? [])) Channel.fromJson((x as Map).cast<String, dynamic>())];
      loaded = true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markSeen(String id) async {
    final t = DateTime.now().millisecondsSinceEpoch;
    _seen[id] = t;
    final p = await SharedPreferences.getInstance();
    await p.setInt('ch_seen_$id', t);
    notifyListeners();
  }

  Timer? _soon;
  final _postListeners = <String, VoidCallback>{};
  void listen(String id, VoidCallback f) => _postListeners[id] = f;
  void unlisten(String id) => _postListeners.remove(id);

  void onNewPost(String channelId) {
    _postListeners[channelId]?.call();
    _soon?.cancel();
    _soon = Timer(const Duration(seconds: 2), refresh);
  }

  Future<List<Channel>> explore(String q) async {
    final d = await Api.instance.request('GET', '/v1/channels/explore${q.isEmpty ? '' : '?q=${Uri.encodeQueryComponent(q)}'}');
    return [for (final x in (d['channels'] as List? ?? [])) Channel.fromJson((x as Map).cast<String, dynamic>())];
  }

  Future<(Channel, List<ChannelPost>)> open(String id) async {
    final d = await Api.instance.request('GET', '/v1/channels/$id');
    return (
      Channel.fromJson((d['channel'] as Map).cast<String, dynamic>()),
      [for (final x in (d['posts'] as List? ?? [])) ChannelPost.fromJson((x as Map).cast<String, dynamic>())],
    );
  }

  Future<Channel> create(String name, String description) async {
    final d = await Api.instance.request('POST', '/v1/channels', {'name': name, 'description': description});
    final c = Channel.fromJson((d['channel'] as Map).cast<String, dynamic>());
    await refresh();
    return c;
  }

  Future<void> follow(String id, bool on) async {
    await Api.instance.request(on ? 'POST' : 'DELETE', '/v1/channels/$id/follow');
    await refresh();
  }

  Future<void> post(String id, String text, {Map<String, dynamic>? media}) async {
    await Api.instance.request('POST', '/v1/channels/$id/posts', {'text': text, if (media != null) 'media': media});
    unawaited(refresh());
  }

  Future<void> deletePost(String id, String postId) => Api.instance.request('DELETE', '/v1/channels/$id/posts/$postId');

  Future<void> react(String id, String postId, String? emoji) => Api.instance.request('POST', '/v1/channels/$id/posts/$postId/react', {'emoji': emoji});

  Future<void> delete(String id) async {
    await Api.instance.request('DELETE', '/v1/channels/$id');
    await refresh();
  }
}
