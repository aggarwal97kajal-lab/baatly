-- Group settings (WhatsApp-style): who can edit group info / send messages.
ALTER TABLE groups ADD COLUMN edit_info TEXT NOT NULL DEFAULT 'admins';   -- 'all' | 'admins'
ALTER TABLE groups ADD COLUMN send_messages TEXT NOT NULL DEFAULT 'all';  -- 'all' | 'admins'
