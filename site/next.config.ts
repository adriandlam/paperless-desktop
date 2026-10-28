import type { NextConfig } from "next";

const nextConfig: NextConfig = {
	// Plain HTML in out/, for GitHub Pages
	output: "export",
	// Pages serves the site under /paperless-desktop; the workflow sets this, `next dev` leaves it empty
	basePath: process.env.PAGES_BASE_PATH,
	images: { unoptimized: true },
};

export default nextConfig;
