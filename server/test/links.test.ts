import { describe, expect, it } from "vitest";
import { buildLinks } from "../src/links";
import type { Upload } from "../src/uploads";

const BASE = "https://share.example.com";
const image: Upload = {
	id: "AbCdEfGhIjKl",
	kind: "image",
	contentType: "image/png",
	extension: "png",
	size: 10,
	hasGif: false,
	createdAt: 0,
};
const video: Upload = { ...image, kind: "video", contentType: "video/mp4", extension: "mp4" };

describe("buildLinks", () => {
	it("links images directly in Markdown", () => {
		expect(buildLinks(image, BASE)).toEqual({
			page: `${BASE}/AbCdEfGhIjKl`,
			file: `${BASE}/AbCdEfGhIjKl.png`,
			gif: null,
			markdown: `![Screenshot](${BASE}/AbCdEfGhIjKl.png)`,
		});
	});

	it("links videos without a GIF to the share page", () => {
		expect(buildLinks(video, BASE)).toEqual({
			page: `${BASE}/AbCdEfGhIjKl`,
			file: `${BASE}/AbCdEfGhIjKl.mp4`,
			gif: null,
			markdown: `[Recording](${BASE}/AbCdEfGhIjKl)`,
		});
	});

	it("embeds the GIF, with its version, for videos that have one", () => {
		expect(buildLinks({ ...video, hasGif: true, gifVersion: 1791555300000 }, BASE)).toEqual({
			page: `${BASE}/AbCdEfGhIjKl`,
			file: `${BASE}/AbCdEfGhIjKl.mp4`,
			gif: `${BASE}/AbCdEfGhIjKl.gif?v=1791555300000`,
			markdown: `[![Recording](${BASE}/AbCdEfGhIjKl.gif?v=1791555300000)](${BASE}/AbCdEfGhIjKl)`,
		});
	});

	it("links GIFs made before versioning without a version", () => {
		expect(buildLinks({ ...video, hasGif: true }, BASE).gif).toBe(`${BASE}/AbCdEfGhIjKl.gif`);
	});
});
