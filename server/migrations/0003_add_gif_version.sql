-- Migration number: 0003
-- Gives each GIF version its own URL (?v=...), so caches fetch a replacement.
ALTER TABLE uploads ADD COLUMN gif_version INTEGER NOT NULL DEFAULT 0;
