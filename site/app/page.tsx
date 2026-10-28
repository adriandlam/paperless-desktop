import Image from "next/image";
import icon from "./icon.png";
import finder from "./shots/finder.png";
import menu from "./shots/menu.png";
import settings from "./shots/settings.png";

const repo = "https://github.com/adriandlam/paperless-desktop";

const rows = [
	{
		image: finder,
		alt: "A Finder window open on Paperless, showing receipts as files with thumbnails",
		title: "Paperless in the Finder sidebar",
		text: [
			"Paperless Desktop adds your server as a location in Finder's sidebar, with folders for All Documents, Correspondents, Tags, Document Types and Years. Documents show Paperless's own thumbnails, and download only when you open them.",
			"Drop a file into any folder to upload it. Dropping it into a tag, correspondent or document type folder sets that on the new document.",
		],
	},
	{
		image: menu,
		alt: "The menu bar menu: Last synced today at 13:07, Sync Now, Open in Finder, Settings, Quit",
		title: "Lives in the menu bar",
		text: [
			"A leaf in the menu bar shows when your library last synced, with Sync Now, Open in Finder and Settings. It gets a ! when a sync fails.",
			"Paperless is checked for changes every 5 minutes, or as often as you choose.",
		],
	},
	{
		image: settings,
		alt: "The Settings window: server, sign-in, offline and sync options",
		title: "Connect to your Paperless server",
		text: [
			"Enter your server URL and sign in with your username and password, or an API token. The password is used once, to get a token that's kept in the Keychain.",
			"Turn on Make all documents available offline to keep the whole library on your Mac.",
		],
	},
];

const reasons = [
	{
		title: "Native Finder integration",
		text: "Built on Apple's File Provider system, so documents behave like real files in Finder, Quick Look and open dialogs.",
	},
	{
		title: "Move to Trash",
		text: "Trash a document in All Documents and it goes to Paperless's trash, shown in Finder's Trash. Put Back restores it.",
	},
	{
		title: "Talks only to your server",
		text: "No accounts and no third-party servers. The app connects straight to your Paperless-ngx server.",
	},
	{
		title: "Free and open source",
		text: "MIT licensed. Build it from source with Xcode in about two minutes.",
	},
];

const questions = [
	{
		q: "Is this an official Paperless-ngx app?",
		a: "No. It's an independent app that talks to your server's API, the same one the Paperless web app uses.",
	},
	{
		q: "What do I need?",
		a: "A Mac on macOS 15 or later, and a Paperless-ngx server on version 3.0 or later.",
	},
	{
		q: "Can it change or delete my documents?",
		a: "It uploads the files you drop in. Move to Trash in All Documents sends a document to Paperless's trash, which shows up in Finder's Trash: Put Back restores it, and emptying the Trash deletes it for good. Nothing else changes in Paperless.",
	},
	{
		q: "How do I install it?",
		a: "There's no signed download yet, so you build it from source with Xcode. The steps are in the README.",
	},
];

export default function Home() {
	return (
		<main className="px-6 text-neutral-900">
			<header className="fade-in flex flex-col items-center pt-20 pb-16 text-center">
				<Image src={icon} alt="" width={112} height={112} />
				<h1 className="mt-5 font-semibold text-4xl tracking-tight">
					Paperless Desktop
				</h1>
				<p className="mt-4 max-w-lg text-lg text-neutral-600">
					Your documents from Paperless-ngx, right in the macOS Finder.
				</p>
				<div className="mt-8 flex gap-3">
					<a
						href={`${repo}#install`}
						className="rounded-lg bg-leaf px-5 py-2.5 font-medium text-white transition-opacity hover:opacity-85"
					>
						Install
					</a>
					<a
						href={repo}
						className="rounded-lg border border-neutral-300 px-5 py-2.5 font-medium transition-colors hover:bg-neutral-100"
					>
						View on GitHub
					</a>
				</div>
				<p className="mt-5 flex gap-5 text-neutral-500 text-sm">
					<a
						href={`${repo}/issues`}
						className="transition-colors hover:text-neutral-900"
					>
						Report an issue
					</a>
					<a href={repo} className="transition-colors hover:text-neutral-900">
						View source
					</a>
				</p>
			</header>

			<div className="mx-auto max-w-4xl space-y-24 py-8">
				{rows.map((r, i) => (
					<section
						key={r.title}
						className="reveal grid items-center gap-10 md:grid-cols-2"
					>
						<Image
							src={r.image}
							alt={r.alt}
							// Retina screenshots: never show them past their real size
							style={{ maxWidth: r.image.width / 2 }}
							className={`mx-auto h-auto w-full ${i % 2 ? "md:order-last" : ""}`}
						/>
						<div>
							<h2 className="font-semibold text-2xl tracking-tight">
								{r.title}
							</h2>
							{r.text.map((t) => (
								<p key={t} className="mt-4 text-neutral-600 leading-relaxed">
									{t}
								</p>
							))}
						</div>
					</section>
				))}
			</div>

			<section className="reveal mx-auto max-w-4xl py-24">
				<h2 className="text-center font-semibold text-2xl tracking-tight">
					Why Paperless Desktop
				</h2>
				<div className="mt-10 grid gap-4 sm:grid-cols-2">
					{reasons.map((r) => (
						<div
							key={r.title}
							className="rounded-xl border border-neutral-200 p-6 transition-colors hover:border-neutral-300"
						>
							<h3 className="font-semibold">{r.title}</h3>
							<p className="mt-2 text-neutral-600 leading-relaxed">{r.text}</p>
						</div>
					))}
				</div>
			</section>

			<section className="reveal mx-auto max-w-2xl pb-24">
				<h2 className="text-center font-semibold text-2xl tracking-tight">
					Frequently asked questions
				</h2>
				<div className="mt-8 divide-y divide-neutral-200 border-neutral-200 border-y">
					{questions.map(({ q, a }) => (
						<details key={q} className="group">
							<summary className="flex cursor-pointer list-none justify-between gap-4 py-4 font-medium">
								{q}
								<span className="text-neutral-400 transition-transform duration-200 group-open:rotate-45">
									+
								</span>
							</summary>
							<p className="pb-4 text-neutral-600 leading-relaxed">{a}</p>
						</details>
					))}
				</div>
			</section>

			<footer className="pb-10 text-center text-neutral-500 text-sm">
				Not affiliated with Paperless-ngx. MIT licensed.
			</footer>
		</main>
	);
}
