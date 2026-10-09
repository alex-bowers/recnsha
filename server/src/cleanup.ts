import { deleteUpload, gifKey, listPendingCreatedBefore, originalKey, type StoredUpload } from "./uploads";

/** Pending uploads older than this are treated as abandoned, for example after a crash or lost connection. */
const ABANDONED_AFTER_MS = 24 * 60 * 60 * 1000;

/** Removes an upload's stored files, any unfinished multipart upload, and its row. */
export async function discardUpload(env: Env, upload: StoredUpload): Promise<void> {
	if (upload.multipartUploadId !== null) {
		try {
			await env.BUCKET.resumeMultipartUpload(originalKey(upload), upload.multipartUploadId).abort();
		} catch (error) {
			// R2 removes unfinished multipart uploads after 7 days, so it may already be gone.
			console.warn("Could not abort multipart upload", upload.id, error);
		}
	}
	await env.BUCKET.delete([originalKey(upload), gifKey(upload.id)]);
	await deleteUpload(env.DB, upload.id);
}

/** Removes pending uploads that were started over a day ago and never completed. Returns how many. */
export async function cleanUpAbandonedUploads(env: Env, now: number): Promise<number> {
	const abandoned = await listPendingCreatedBefore(env.DB, now - ABANDONED_AFTER_MS);
	for (const upload of abandoned) {
		await discardUpload(env, upload);
	}
	return abandoned.length;
}
