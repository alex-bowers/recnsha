import type { Upload } from "./uploads";

export interface Links {
	page: string;
	file: string;
	gif: string | null;
	markdown: string;
}

/**
 * The GIF's path, with its version so a replaced GIF gets a new URL and caches fetch it.
 * The Worker ignores the query string when serving the file.
 */
export function gifPath(upload: Pick<Upload, "id" | "gifVersion">): string {
	return upload.gifVersion ? `/${upload.id}.gif?v=${upload.gifVersion}` : `/${upload.id}.gif`;
}

export function buildLinks(upload: Upload, baseUrl: string): Links {
	const page = `${baseUrl}/${upload.id}`;
	const file = `${page}.${upload.extension}`;
	const gif = upload.kind === "video" && upload.hasGif ? `${baseUrl}${gifPath(upload)}` : null;

	let markdown: string;
	if (upload.kind === "image") {
		markdown = `![Screenshot](${file})`;
	} else if (gif !== null) {
		markdown = `[![Recording](${gif})](${page})`;
	} else {
		markdown = `[Recording](${page})`;
	}

	return { page, file, gif, markdown };
}
