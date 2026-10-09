import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { generateId } from "../src/ids";
import {
	addPendingBytes,
	deleteUpload,
	findUpload,
	gifKey,
	insertUpload,
	listReadyUploads,
	markHasGif,
	markReady,
	originalKey,
	storageUsed,
	type Upload,
} from "../src/uploads";

function makeUpload(overrides: Partial<Upload> = {}): Upload {
	return {
		id: generateId(),
		kind: "image",
		contentType: "image/png",
		extension: "png",
		size: 10,
		hasGif: false,
		createdAt: Date.now(),
		...overrides,
	};
}

const video = { kind: "video", contentType: "video/mp4", extension: "mp4" } as const;

describe("uploads table", () => {
	it("stores and finds an upload", async () => {
		const upload = makeUpload();
		await insertUpload(env.DB, upload, "ready");

		expect(await findUpload(env.DB, upload.id)).toMatchObject({
			...upload,
			status: "ready",
			multipartUploadId: null,
		});
		expect(await findUpload(env.DB, generateId())).toBeNull();
	});

	it("lists ready uploads newest first and pages with a cursor", async () => {
		const first = makeUpload();
		const pending = makeUpload({ ...video, size: 0 });
		const second = makeUpload();
		await insertUpload(env.DB, first, "ready");
		await insertUpload(env.DB, pending, "pending", "multipart-123");
		await insertUpload(env.DB, second, "ready");

		const page = await listReadyUploads(env.DB, null, 2);
		expect(page.map((upload) => upload.id)).toEqual([second.id, first.id]);

		const next = await listReadyUploads(env.DB, page[1].cursor, 10);
		expect(next.map((upload) => upload.id)).not.toContain(first.id);
		expect(next.map((upload) => upload.id)).not.toContain(pending.id);
	});

	it("marks multipart uploads ready and records GIF previews", async () => {
		const upload = makeUpload({ ...video, size: 0 });
		await insertUpload(env.DB, upload, "pending", "multipart-456");
		await markReady(env.DB, upload.id, 1234);
		await markHasGif(env.DB, upload.id, 99, 1791555300000);

		expect(await findUpload(env.DB, upload.id)).toMatchObject({
			status: "ready",
			size: 1234,
			hasGif: true,
			gifSize: 99,
			gifVersion: 1791555300000,
			multipartUploadId: null,
		});
	});

	it("totals stored bytes, including GIFs and unfinished uploads", async () => {
		const before = await storageUsed(env.DB);
		const image = makeUpload({ size: 1000 });
		const recording = makeUpload({ ...video, size: 0 });
		await insertUpload(env.DB, image, "ready");
		await insertUpload(env.DB, recording, "pending", "multipart-789");

		await addPendingBytes(env.DB, recording.id, 500);
		await addPendingBytes(env.DB, image.id, 10_000);
		expect(await storageUsed(env.DB)).toBe(before + 1500);

		await markReady(env.DB, recording.id, 600);
		await markHasGif(env.DB, recording.id, 40, Date.now());
		expect(await storageUsed(env.DB)).toBe(before + 1640);

		await deleteUpload(env.DB, image.id);
		expect(await storageUsed(env.DB)).toBe(before + 640);
	});

	it("keeps the running total equal to the sum of every row", async () => {
		const upload = makeUpload({ size: 123 });
		await insertUpload(env.DB, upload, "ready");
		await markHasGif(env.DB, upload.id, 7, Date.now());
		await deleteUpload(env.DB, upload.id);

		const row = await env.DB.prepare(`SELECT COALESCE(SUM(size + gif_size), 0) AS total FROM uploads`).first<{ total: number }>();
		expect(await storageUsed(env.DB)).toBe(row?.total);
	});

	it("deletes uploads", async () => {
		const upload = makeUpload();
		await insertUpload(env.DB, upload, "ready");
		await deleteUpload(env.DB, upload.id);
		expect(await findUpload(env.DB, upload.id)).toBeNull();
	});

	it("names R2 keys by ID", () => {
		expect(originalKey({ id: "AbCdEfGhIjKl", extension: "png" })).toBe("AbCdEfGhIjKl/original.png");
		expect(gifKey("AbCdEfGhIjKl")).toBe("AbCdEfGhIjKl/preview.gif");
	});
});
