-- Migration number: 0001
CREATE TABLE uploads (
	id TEXT PRIMARY KEY,
	kind TEXT NOT NULL CHECK (kind IN ('image', 'video')),
	content_type TEXT NOT NULL,
	extension TEXT NOT NULL,
	size INTEGER NOT NULL DEFAULT 0,
	has_gif INTEGER NOT NULL DEFAULT 0,
	status TEXT NOT NULL CHECK (status IN ('pending', 'ready')),
	multipart_upload_id TEXT,
	created_at INTEGER NOT NULL
);
