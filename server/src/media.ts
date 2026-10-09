export type Kind = "image" | "video";

export interface MediaType {
	contentType: string;
	kind: Kind;
	extension: string;
}

// Only formats browsers render without running scripts. Never add text/html or image/svg+xml.
const MEDIA_TYPES = new Map<string, MediaType>([
	["image/png", { contentType: "image/png", kind: "image", extension: "png" }],
	["image/jpeg", { contentType: "image/jpeg", kind: "image", extension: "jpg" }],
	["image/gif", { contentType: "image/gif", kind: "image", extension: "gif" }],
	["video/mp4", { contentType: "video/mp4", kind: "video", extension: "mp4" }],
]);

export function mediaTypeFor(contentType: string | null): MediaType | null {
	if (contentType === null) return null;
	const essence = contentType.split(";")[0].trim().toLowerCase();
	return MEDIA_TYPES.get(essence) ?? null;
}
