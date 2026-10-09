-- Migration number: 0004
-- Keeps a running storage total so the quota check reads one row instead of summing every upload.
CREATE TABLE storage_usage (
	id INTEGER PRIMARY KEY CHECK (id = 1),
	bytes INTEGER NOT NULL
);

INSERT INTO storage_usage (id, bytes) SELECT 1, COALESCE(SUM(size + gif_size), 0) FROM uploads;

CREATE TRIGGER storage_usage_after_insert AFTER INSERT ON uploads
BEGIN
	UPDATE storage_usage SET bytes = bytes + NEW.size + NEW.gif_size WHERE id = 1;
END;

CREATE TRIGGER storage_usage_after_update AFTER UPDATE OF size, gif_size ON uploads
BEGIN
	UPDATE storage_usage SET bytes = bytes + (NEW.size + NEW.gif_size) - (OLD.size + OLD.gif_size) WHERE id = 1;
END;

CREATE TRIGGER storage_usage_after_delete AFTER DELETE ON uploads
BEGIN
	UPDATE storage_usage SET bytes = bytes - (OLD.size + OLD.gif_size) WHERE id = 1;
END;
