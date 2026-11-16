CREATE TABLE IF NOT EXISTS photos (
  id TEXT PRIMARY KEY,
  sender_id TEXT NOT NULL,
  object_key TEXT NOT NULL UNIQUE,
  mime_type TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS photo_recipients (
  photo_id TEXT NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  viewed_at INTEGER,
  PRIMARY KEY(photo_id,user_id)
);
CREATE INDEX IF NOT EXISTS idx_photos_expiry ON photos(expires_at);
CREATE INDEX IF NOT EXISTS idx_photo_recipients_user ON photo_recipients(user_id,photo_id);
