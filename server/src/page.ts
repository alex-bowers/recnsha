import { buildLinks, gifPath } from "./links";
import type { Upload } from "./uploads";

const CONTENT_SECURITY_POLICY =
	"default-src 'none'; img-src 'self'; media-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

const STYLES = `
:root { color-scheme: light dark; --bg: #f4f4f5; --fg: #18181b; --link: #1d4ed8; }
@media (prefers-color-scheme: dark) { :root { --bg: #18181b; --fg: #f4f4f5; --link: #93c5fd; } }
body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.5 system-ui, sans-serif; }
main { box-sizing: border-box; min-height: 100vh; display: grid; place-items: center; align-content: center; gap: 12px; padding: 16px; }
img, video { max-width: 100%; max-height: 85vh; height: auto; }
a { color: var(--link); }
a:focus-visible { outline: 2px solid currentColor; outline-offset: 2px; }
`;

const HTML_ESCAPES: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };

function escapeHtml(value: string): string {
	return value.replace(/[&<>"']/g, (character) => HTML_ESCAPES[character]);
}

export function renderPage(upload: Upload, baseUrl: string): Response {
	const links = buildLinks(upload, baseUrl);
	const title = upload.kind === "image" ? "Screenshot" : "Recording";
	// The page's own media uses relative paths so it works on any host; preview tags need absolute URLs.
	const localFile = escapeHtml(`/${upload.id}.${upload.extension}`);
	const preview = upload.kind === "image" ? links.file : links.gif;

	const meta = [
		`<meta property="og:title" content="${title}">`,
		`<meta property="og:url" content="${escapeHtml(links.page)}">`,
		`<meta property="og:type" content="${upload.kind === "image" ? "website" : "video.other"}">`,
	];
	if (preview !== null) {
		meta.push(`<meta property="og:image" content="${escapeHtml(preview)}">`);
		meta.push(`<meta name="twitter:card" content="summary_large_image">`);
	}
	if (upload.kind === "video") {
		meta.push(`<meta property="og:video" content="${escapeHtml(links.file)}">`);
		meta.push(`<meta property="og:video:type" content="${escapeHtml(upload.contentType)}">`);
	}

	const media =
		upload.kind === "image"
			? `<img src="${localFile}" alt="Screenshot">`
			: `<video src="${localFile}" controls autoplay muted loop playsinline></video>`;
	const gifLink = links.gif === null ? "" : ` · <a href="${escapeHtml(gifPath(upload))}">GIF</a>`;

	const html = `<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${title}</title>
${meta.join("\n")}
<style>${STYLES}</style>
</head>
<body>
<main>
${media}
<p><a href="${localFile}">Original</a>${gifLink}</p>
</main>
</body>
</html>`;

	return new Response(html, {
		headers: {
			"Content-Type": "text/html; charset=utf-8",
			"Cache-Control": "public, max-age=60",
			"Content-Security-Policy": CONTENT_SECURITY_POLICY,
		},
	});
}
