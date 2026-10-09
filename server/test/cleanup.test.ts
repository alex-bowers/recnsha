import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { cleanUpAbandonedUploads } from "../src/cleanup";
import { generateId } from "../src/ids";
import { findUpload, insertUpload, type Upload } from "../src/uploads";
import { request } from "./helpers";

const DAY = 24 * 60 * 60 * 1000;

function makeVideo(createdAt: number): Upload {
	return { id: generateId(), kind: "video", contentType: "video/mp4", extension: "mp4", size: 500, hasGif: false, createdAt };
}

describe("abandoned uploads", () => {
	it("can be deleted even when the multipart upload no longer exists", async () => {
		const upload = makeVideo(Date.now());
		await insertUpload(env.DB, upload, "pending", "expired-multipart-id");

		const response = await request(`/api/uploads/${upload.id}`, { method: "DELETE" });

		expect(response.status).toBe(204);
		expect(await findUpload(env.DB, upload.id)).toBeNull();
	});

	it("are removed by the daily clean-up once older than a day", async () => {
		const now = Date.now();
		const stale = makeVideo(now - 2 * DAY);
		const recent = makeVideo(now - 60_000);
		const finished = makeVideo(now - 2 * DAY);
		await insertUpload(env.DB, stale, "pending", "expired-multipart-id");
		await insertUpload(env.DB, recent, "pending", "active-multipart-id");
		await insertUpload(env.DB, finished, "ready");

		const removed = await cleanUpAbandonedUploads(env, now);

		expect(removed).toBe(1);
		expect(await findUpload(env.DB, stale.id)).toBeNull();
		expect(await findUpload(env.DB, recent.id)).not.toBeNull();
		expect(await findUpload(env.DB, finished.id)).not.toBeNull();
	});
});
