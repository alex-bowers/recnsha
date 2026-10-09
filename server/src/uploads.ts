import type { Kind } from "./media";

export type Status = "pending" | "ready";

export interface Upload {
	id: string;
	kind: Kind;
	contentType: string;
	extension: string;
	size: number;
	hasGif: boolean;
	/** When the GIF was last uploaded, in milliseconds; absent or 0 for GIFs made before versioning. */
	gifVersion?: number;
	createdAt: number;
}

export interface StoredUpload extends Upload {
	cursor: number;
	gifSize: number;
	status: Status;
	multipartUploadId: string | null;
}

interface UploadRow {
	cursor: number;
	id: string;
	kind: Kind;
	content_type: string;
	extension: string;
	size: number;
	has_gif: number;
	gif_size: number;
	gif_version: number;
	status: Status;
	multipart_upload_id: string | null;
	created_at: number;
}

const SELECT_UPLOADS = `SELECT rowid AS cursor, id, kind, content_type, extension, size, has_gif, gif_size, gif_version, status, multipart_upload_id, created_at FROM uploads`;

function fromRow(row: UploadRow): StoredUpload {
	return {
		cursor: row.cursor,
		id: row.id,
		kind: row.kind,
		contentType: row.content_type,
		extension: row.extension,
		size: row.size,
		hasGif: row.has_gif === 1,
		gifSize: row.gif_size,
		gifVersion: row.gif_version,
		createdAt: row.created_at,
		status: row.status,
		multipartUploadId: row.multipart_upload_id,
	};
}

export function originalKey(upload: Pick<Upload, "id" | "extension">): string {
	return `${upload.id}/original.${upload.extension}`;
}

export function gifKey(id: string): string {
	return `${id}/preview.gif`;
}

export async function insertUpload(
	db: D1Database,
	upload: Upload,
	status: Status,
	multipartUploadId: string | null = null,
): Promise<void> {
	await db
		.prepare(
			`INSERT INTO uploads (id, kind, content_type, extension, size, has_gif, status, multipart_upload_id, created_at)
			VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)`,
		)
		.bind(
			upload.id,
			upload.kind,
			upload.contentType,
			upload.extension,
			upload.size,
			upload.hasGif ? 1 : 0,
			status,
			multipartUploadId,
			upload.createdAt,
		)
		.run();
}

export async function findUpload(db: D1Database, id: string): Promise<StoredUpload | null> {
	const row = await db.prepare(`${SELECT_UPLOADS} WHERE id = ?1`).bind(id).first<UploadRow>();
	return row === null ? null : fromRow(row);
}

export async function listReadyUploads(
	db: D1Database,
	before: number | null,
	limit: number,
): Promise<StoredUpload[]> {
	const statement =
		before === null
			? db.prepare(`${SELECT_UPLOADS} WHERE status = 'ready' ORDER BY rowid DESC LIMIT ?1`).bind(limit)
			: db
					.prepare(`${SELECT_UPLOADS} WHERE status = 'ready' AND rowid < ?2 ORDER BY rowid DESC LIMIT ?1`)
					.bind(limit, before);
	const { results } = await statement.all<UploadRow>();
	return results.map(fromRow);
}

export async function markReady(db: D1Database, id: string, size: number): Promise<void> {
	await db
		.prepare(`UPDATE uploads SET status = 'ready', size = ?2, multipart_upload_id = NULL WHERE id = ?1`)
		.bind(id, size)
		.run();
}

export async function markHasGif(db: D1Database, id: string, gifSize: number, gifVersion: number): Promise<void> {
	await db
		.prepare(`UPDATE uploads SET has_gif = 1, gif_size = ?2, gif_version = ?3 WHERE id = ?1`)
		.bind(id, gifSize, gifVersion)
		.run();
}

/** Records bytes received for an unfinished multipart upload so they count towards the storage cap. */
export async function addPendingBytes(db: D1Database, id: string, bytes: number): Promise<void> {
	await db.prepare(`UPDATE uploads SET size = size + ?2 WHERE id = ?1 AND status = 'pending'`).bind(id, bytes).run();
}

/**
 * Total bytes stored: originals, GIF previews and parts of unfinished uploads.
 * Triggers on `uploads` keep this one-row total current (migration 0004).
 */
export async function storageUsed(db: D1Database): Promise<number> {
	const row = await db.prepare(`SELECT bytes FROM storage_usage WHERE id = 1`).first<{ bytes: number }>();
	return row?.bytes ?? 0;
}

export async function listPendingCreatedBefore(db: D1Database, before: number): Promise<StoredUpload[]> {
	const { results } = await db
		.prepare(`${SELECT_UPLOADS} WHERE status = 'pending' AND created_at < ?1`)
		.bind(before)
		.all<UploadRow>();
	return results.map(fromRow);
}

export async function deleteUpload(db: D1Database, id: string): Promise<void> {
	await db.prepare(`DELETE FROM uploads WHERE id = ?1`).bind(id).run();
}
