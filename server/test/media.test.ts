import { describe, expect, it } from "vitest";
import { mediaTypeFor } from "../src/media";

describe("mediaTypeFor", () => {
	it("maps supported types", () => {
		expect(mediaTypeFor("image/png")).toEqual({ contentType: "image/png", kind: "image", extension: "png" });
		expect(mediaTypeFor("image/jpeg")).toEqual({ contentType: "image/jpeg", kind: "image", extension: "jpg" });
		expect(mediaTypeFor("image/gif")).toEqual({ contentType: "image/gif", kind: "image", extension: "gif" });
		expect(mediaTypeFor("video/mp4")).toEqual({ contentType: "video/mp4", kind: "video", extension: "mp4" });
	});

	it("ignores parameters and letter case", () => {
		expect(mediaTypeFor("Image/PNG; charset=binary")?.extension).toBe("png");
	});

	it("rejects everything else", () => {
		for (const value of [null, "", "text/html", "image/svg+xml", "constructor"]) {
			expect(mediaTypeFor(value)).toBeNull();
		}
	});
});
