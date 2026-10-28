import Image from "next/image";
import icon from "./icon.png";
import finder from "./shots/finder.png";
import menu from "./shots/menu.png";
import settings from "./shots/settings.png";

const repo = "https://github.com/adriandlam/paperless-desktop";

const features = [
	{
		title: "In the Finder sidebar",
		text: "Folders for All Documents, Correspondents, Tags, Document Types and Years. A document shows up in every folder it belongs to.",
	},
	{
		title: "Opens like any file",
		text: "Documents download when you open them, with thumbnails and Quick Look from Paperless's own previews.",
	},
	{
		title: "Available offline",
		text: "Right-click a folder and choose Keep Downloaded, or keep the whole library on your Mac.",
	},
	{
		title: "Drag in to upload",
		text: "Drop a file into any folder and Paperless consumes it. Drop it into a tag, correspondent or document type and the new document gets that too.",
	},
	{
		title: "Paperless tags in Finder",
		text: "Each document's Paperless tags show up as Finder tags.",
	},
	{
		title: "Signs in once",
		text: "Your password is used once, to get an API token that's kept in the Keychain.",
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
		a: "There's no signed download yet, so you build it from source with Xcode. It takes about two minutes, and the steps are in the README.",
	},
	{
		q: "How often does it sync?",
		a: "Every 5 minutes by default, which you can change in Settings. Sync Now in the menu bar checks right away.",
	},
];

export default function Home() {
	return (
		<main className="px-6 [&>*]:mx-auto [&>*]:max-w-3xl">
			<header className="flex flex-col items-center pt-24 pb-16 text-center">
				<Image src={icon} alt="" width={128} height={128} />
				<h1 className="mt-6 font-semibold text-5xl tracking-tight">
					Paperless Desktop
				</h1>
				<p className="mt-4 text-neutral-600 text-xl dark:text-neutral-400">
					Your Paperless-ngx library in Finder, the way iCloud Drive is.
				</p>
				<div className="mt-8 flex gap-3">
					<a
						href={`${repo}#install`}
						className="rounded-full bg-leaf px-5 py-2.5 font-medium text-white hover:opacity-90"
					>
						Install
					</a>
					<a
						href={repo}
						className="rounded-full px-5 py-2.5 font-medium ring-1 ring-neutral-300 hover:bg-neutral-100 dark:ring-neutral-700 dark:hover:bg-neutral-900"
					>
						View on GitHub
					</a>
				</div>
				<p className="mt-4 text-neutral-500 text-sm">
					Free and open source. macOS 15 or later.
				</p>
			</header>

			<Image
				src={finder}
				alt="A Finder window open on Paperless, showing receipts as files with thumbnails"
				className="h-auto w-full max-w-5xl!"
			/>

			<section className="grid gap-10 py-16 sm:grid-cols-2">
				{features.map((f) => (
					<div key={f.title}>
						<h2 className="font-semibold">{f.title}</h2>
						<p className="mt-1 text-neutral-600 dark:text-neutral-400">
							{f.text}
						</p>
					</div>
				))}
			</section>

			<section className="grid items-start gap-10 border-neutral-200 border-t py-16 sm:grid-cols-2 dark:border-neutral-800">
				<figure>
					<Image
						src={menu}
						alt="The menu bar menu: Last synced today at 13:07, Sync Now, Open in Finder, Settings, Quit"
						className="h-auto w-full"
					/>
					<figcaption className="mt-3 text-neutral-600 dark:text-neutral-400">
						The leaf in the menu bar shows when the library last synced, and
						gets a ! if a sync fails.
					</figcaption>
				</figure>
				<figure>
					<Image
						src={settings}
						alt="The Settings window: server, sign-in, offline and sync options"
						className="h-auto w-full"
					/>
					<figcaption className="mt-3 text-neutral-600 dark:text-neutral-400">
						Sign in with a password or an API token, and choose how often to
						check for changes.
					</figcaption>
				</figure>
			</section>

			<section className="border-neutral-200 border-t py-16 dark:border-neutral-800">
				<h2 className="font-semibold text-2xl tracking-tight">Questions</h2>
				<div className="mt-6 divide-y divide-neutral-200 dark:divide-neutral-800">
					{questions.map(({ q, a }) => (
						<details key={q} className="group py-4">
							<summary className="flex cursor-pointer list-none justify-between gap-4 font-medium">
								{q}
								<span className="text-neutral-400 transition-transform group-open:rotate-45">
									+
								</span>
							</summary>
							<p className="mt-2 text-neutral-600 dark:text-neutral-400">{a}</p>
						</details>
					))}
				</div>
			</section>

			<footer className="flex justify-between border-neutral-200 border-t py-10 text-neutral-500 text-sm dark:border-neutral-800">
				<span>Not affiliated with Paperless-ngx. MIT licensed.</span>
				<a
					href={repo}
					className="hover:text-neutral-900 dark:hover:text-neutral-100"
				>
					GitHub
				</a>
			</footer>
		</main>
	);
}
