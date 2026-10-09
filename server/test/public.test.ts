import { describe, expect, it } from "vitest";
import { GIF_BYTES, PNG_BYTES, request, uploadImage, uploadVideo } from "./helpers";

function publicGet(path: string, headers: HeadersInit = {}): Promise<Response> {
	return request(path, { headers }, null);
}

describe("share page", () => {
	it("renders an image page with link-preview tags", async () => {
		const upload = await uploadImage();
		const response = await publicGet(`/${upload.id}`);

		expect(response.status).toBe(200);
		expect(response.headers.get("Content-Type")).toBe("text/html; charset=utf-8");
		expect(response.headers.get("Content-Security-Policy")).toContain("default-src 'none'");
		expect(response.headers.get("X-Content-Type-Options")).toBe("nosniff");

		const html = await response.text();
		expect(html).toContain(`<meta property="og:image" content="${upload.file}">`);
		expect(html).toContain(`<img src="/${upload.id}.png" alt="Screenshot">`);
	});

	it("renders a video page that uses the GIF as its preview", async () => {
		const upload = await uploadVideo({ withGif: true });
		const html = await (await publicGet(`/${upload.id}`)).text();

		expect(html).toContain(`<meta property="og:video" content="${upload.file}">`);
		expect(html).toContain(`<meta property="og:image" content="${upload.gif}">`);
		expect(html).toContain(`<video src="/${upload.id}.mp4" controls`);
		expect(html).toContain(`<a href="${new URL(upload.gif!).pathname}${new URL(upload.gif!).search}">GIF</a>`);
	});

	it("returns 404 for unknown and malformed IDs", async () => {
		expect((await publicGet("/AAAAAAAAAAAA")).status).toBe(404);
		expect((await publicGet("/not-valid")).status).toBe(404);
		expect((await publicGet("/a/b")).status).toBe(404);
	});

	it("only allows GET and HEAD", async () => {
		const upload = await uploadImage();
		const response = await request(`/${upload.id}`, { method: "POST" }, null);
		expect(response.status).toBe(405);
		expect(response.headers.get("Allow")).toBe("GET, HEAD");
	});
});

describe("files", () => {
	it("serves the original with long-lived caching", async () => {
		const upload = await uploadImage();
		const response = await publicGet(`/${upload.id}.png`);

		expect(response.status).toBe(200);
		expect(response.headers.get("Content-Type")).toBe("image/png");
		expect(response.headers.get("Cache-Control")).toBe("public, max-age=31536000, immutable");
		expect(response.headers.get("Accept-Ranges")).toBe("bytes");
		expect(new Uint8Array(await response.arrayBuffer())).toEqual(PNG_BYTES);
	});

	it("supports range requests, which Safari needs for video", async () => {
		const upload = await uploadImage();
		const response = await publicGet(`/${upload.id}.png`, { Range: "bytes=2-5" });

		expect(response.status).toBe(206);
		expect(response.headers.get("Content-Range")).toBe(`bytes 2-5/${PNG_BYTES.byteLength}`);
		expect(new Uint8Array(await response.arrayBuffer())).toEqual(PNG_BYTES.slice(2, 6));
	});

	it("supports suffix range requests", async () => {
		const upload = await uploadImage();
		const response = await publicGet(`/${upload.id}.png`, { Range: "bytes=-4" });

		expect(response.status).toBe(206);
		expect(response.headers.get("Content-Range")).toBe(`bytes 8-11/${PNG_BYTES.byteLength}`);
		expect(new Uint8Array(await response.arrayBuffer())).toEqual(PNG_BYTES.slice(8));
	});

	it("answers conditional requests with 304", async () => {
		const upload = await uploadImage();
		const first = await publicGet(`/${upload.id}.png`);
		await first.arrayBuffer();

		const second = await publicGet(`/${upload.id}.png`, { "If-None-Match": first.headers.get("ETag")! });
		expect(second.status).toBe(304);
	});

	it("answers failed If-Match preconditions with 412, not 304", async () => {
		const upload = await uploadImage();
		const response = await publicGet(`/${upload.id}.png`, { "If-Match": '"not-the-etag"' });
		expect(response.status).toBe(412);
	});

	it("answers ranges beyond the end of the file with 416", async () => {
		const upload = await uploadImage();
		const response = await publicGet(`/${upload.id}.png`, { Range: "bytes=1000-" });
		expect(response.status).toBe(416);
		expect(response.headers.get("Content-Range")).toBe(`bytes */${PNG_BYTES.byteLength}`);
	});

	it("only serves the upload's own extension", async () => {
		const upload = await uploadImage();
		expect((await publicGet(`/${upload.id}.jpg`)).status).toBe(404);
		expect((await publicGet(`/${upload.id}.gif`)).status).toBe(404);
		expect((await publicGet(`/${upload.id}.png.html`)).status).toBe(404);
	});

	it("serves GIF previews for videos", async () => {
		const upload = await uploadVideo({ withGif: true });
		// Served with or without the version query; without it, the GIF may be replaced, so caches refresh.
		const unversioned = await publicGet(`/${upload.id}.gif`);
		expect(unversioned.status).toBe(200);
		expect(unversioned.headers.get("Cache-Control")).toBe("public, max-age=300");
		const response = await publicGet(new URL(upload.gif!).pathname + new URL(upload.gif!).search);

		expect(response.status).toBe(200);
		expect(response.headers.get("Content-Type")).toBe("image/gif");
		// A versioned GIF URL never changes, so it can be cached for good.
		expect(response.headers.get("Cache-Control")).toBe("public, max-age=31536000, immutable");
		expect(new Uint8Array(await response.arrayBuffer())).toEqual(GIF_BYTES);
	});

	it("stops serving deleted uploads", async () => {
		const upload = await uploadImage();
		await request(`/api/uploads/${upload.id}`, { method: "DELETE" });

		expect((await publicGet(`/${upload.id}`)).status).toBe(404);
		expect((await publicGet(`/${upload.id}.png`)).status).toBe(404);
	});
});
