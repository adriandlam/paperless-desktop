import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
	title: "Paperless Desktop",
	description: "Your Paperless-ngx library in Finder, the way iCloud Drive is.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
	return (
		<html lang="en">
			<body className="bg-white text-neutral-900 antialiased dark:bg-neutral-950 dark:text-neutral-100">
				{children}
			</body>
		</html>
	);
}
