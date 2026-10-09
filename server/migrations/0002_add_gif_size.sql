-- Migration number: 0002
-- Lets the storage cap count GIF previews.
ALTER TABLE uploads ADD COLUMN gif_size INTEGER NOT NULL DEFAULT 0;
