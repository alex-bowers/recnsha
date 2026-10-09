import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { generateId } from "../src/ids";
import { deleteUpload, findUpload, insertUpload, storageUsed } from "../src/uploads";
import { GIF_BYTES, PNG_BYTES, request, uploadVideo } from "./helpers";

const LIMIT = env.MAX_STORAGE_GB * 1024 ** 3;
const JSON_HEADERS = { "Content-Type": "application/json" };

/** Fills storage so that `room` bytes remain, runs `check`, then removes the filler. */
async function withRoom(room: number, check: () => Promise<void>): Promise<void> {
	const id = generateId();
	const size = LIMIT - room - (await storageUsed(env.DB));
	await insertUpload(
		env.DB,
		{ id, kind: "image", contentType: "image/png", extension: "png", size, hasGif: false, createdAt: Date.now() },
		"ready",
	);
	try {
		await check();
	} finally {
		await deleteUpload(env.DB, id);
	}
}

function startMultipart(): Promise<Response> {
	return request("/api/uploads/multipart", {
		method: "POST",
		headers: JSON_HEADERS,
		body: JSON.stringify({ contentType: "video/mp4" }),
	});
}

describe("storage cap", () => {
	it("refuses uploads that would pass the limit", async () => {
		await withRoom(PNG_BYTES.byteLength - 1, async () => {
			const response = await request("/api/uploads", {
				method: "POST",
				headers: { "Content-Type": "image/png" },
				body: PNG_BYTES,
			});
			expect(response.status).toBe(507);
			expect(await response.json()).toMatchObject({
				error: `Storage limit of ${env.MAX_STORAGE_GB} GB reached. Delete old uploads to free space.`,
			});
		});
	});

	it("accepts uploads that fit exactly", async () => {
		await withRoom(PNG_BYTES.byteLength, async () => {
			const response = await request("/api/uploads", {
				method: "POST",
				headers: { "Content-Type": "image/png" },
				body: PNG_BYTES,
			});
			expect(response.status).toBe(201);
		});
	});

	it("refuses new multipart uploads once storage is full", async () => {
		await withRoom(0, async () => {
			expect((await startMultipart()).status).toBe(507);
		});
	});

	it("counts parts of unfinished uploads and refuses parts that would pass the limit", async () => {
		const { id } = await (await startMultipart()).json<{ id: string }>();
		expect((await request(`/api/uploads/${id}/parts/1`, { method: "PUT", body: "abc" })).status).toBe(200);
		expect((await findUpload(env.DB, id))?.size).toBe(3);

		await withRoom(2, async () => {
			expect((await request(`/api/uploads/${id}/parts/2`, { method: "PUT", body: "abc" })).status).toBe(507);
		});
		await request(`/api/uploads/${id}`, { method: "DELETE" });
	});

	it("counts only the difference when replacing a GIF", async () => {
		const video = await uploadVideo({ withGif: true });
		const putGif = (body: Uint8Array) =>
			request(`/api/uploads/${video.id}/gif`, { method: "PUT", headers: { "Content-Type": "image/gif" }, body });

		await withRoom(0, async () => {
			expect((await putGif(GIF_BYTES)).status).toBe(200);
			expect((await putGif(new Uint8Array(GIF_BYTES.byteLength + 1))).status).toBe(507);
		});
		await request(`/api/uploads/${video.id}`, { method: "DELETE" });
	});
});
