-- Channels: one-way broadcast, admin posts, followers read and react.
CREATE TABLE channels (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  owner       TEXT NOT NULL,
  followers   INTEGER NOT NULL DEFAULT 0,
  last_post   INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL
);
CREATE INDEX idx_channels_followers ON channels(followers DESC);

CREATE TABLE channel_followers (
  channel_id TEXT NOT NULL,
  user_id    TEXT NOT NULL,
  at         INTEGER NOT NULL,
  PRIMARY KEY (channel_id, user_id)
);
CREATE INDEX idx_chfollow_user ON channel_followers(user_id);

CREATE TABLE channel_posts (
  id         TEXT PRIMARY KEY,
  channel_id TEXT NOT NULL,
  text       TEXT NOT NULL DEFAULT '',
  media      TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_chposts ON channel_posts(channel_id, created_at);

CREATE TABLE channel_reactions (
  post_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  emoji   TEXT NOT NULL,
  PRIMARY KEY (post_id, user_id)
);
