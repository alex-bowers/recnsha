import { errorResponse } from "./http";
import { storageUsed } from "./uploads";

const BYTES_PER_GB = 1024 ** 3;

/** The configured limit in bytes, or null if MAX_STORAGE_GB is missing or invalid. */
export function storageLimitBytes(env: Env): number | null {
	const gigabytes = Number(env.MAX_STORAGE_GB);
	return Number.isFinite(gigabytes) && gigabytes > 0 ? gigabytes * BYTES_PER_GB : null;
}

/**
 * Returns an error response if storing `incomingBytes` more would pass the limit, otherwise null.
 * Pass a negative number when a write shrinks storage, such as a smaller replacement GIF.
 */
export async function checkQuota(env: Env, incomingBytes: number): Promise<Response | null> {
	const limit = storageLimitBytes(env);
	if (limit === null) return errorResponse("Storage limit is not configured", 500);

	const used = await storageUsed(env.DB);
	if (used + incomingBytes > limit) {
		return errorResponse(`Storage limit of ${env.MAX_STORAGE_GB} GB reached. Delete old uploads to free space.`, 507);
	}
	return null;
}
