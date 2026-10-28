# Paperless Desktop

Your [Paperless-ngx](https://docs.paperless-ngx.com) library in Finder, the way iCloud Drive is.

- A Finder location in the sidebar, with folders for All Documents, Correspondents, Tags,
  Document Types and Years. A document shows up in every folder it belongs to.
- Documents download when you open them, with thumbnails and Quick Look from Paperless's own
  previews.
- Offline copies: right-click a folder → Keep Downloaded, or turn on Make all documents available
  offline in Settings to keep the whole library on this Mac.
- Paperless tags show up as Finder tags.
- Drop a file into any folder to upload it. Dropping it into a tag, correspondent or document type
  folder sets that on the new document.
- Move to Trash works in All Documents: the document goes to Paperless's trash and shows up in
  Finder's Trash. Put Back restores it, and emptying the Trash deletes it from Paperless for good.
  Paperless empties its trash after 30 days by default.
- Your password is used once, to get an API token that's kept in the Keychain.

Everything else is read-only: documents can't be renamed, moved, edited, or trashed from other folders.

## Requirements

- macOS 15 or later
- Paperless-ngx 3.0 or later

## Install

There are no release builds yet; build it from source (about two minutes):

```bash
brew install xcodegen
git clone https://github.com/adriandlam/paperless-desktop && cd paperless-desktop
make install
```

`make install` signs with the Apple Developer team in `Signing.xcconfig`. To build under your own
team, create `Local.xcconfig` (it's gitignored) with your team ID and a bundle ID prefix you own:

```
DEVELOPMENT_TEAM = ABCDE12345
BUNDLE_ID_PREFIX = com.example
```

Xcode needs to be signed in to that team (Xcode → Settings → Accounts). Signing has to work,
because the app and its Finder extension share the token through a Keychain group.

## Setup

1. Open Paperless Desktop. Its window asks for your server URL and your Paperless username and
   password (plus a 2FA code if your account has one), or an API token instead.
2. Click **Save**. **Paperless** appears in Finder's sidebar under Locations.

The leaf in the menu bar shows when the library last synced, with Sync Now, Open in Finder and
Settings. It gets a ! when the last sync failed, and is hollow when you're signed out.

Leave the app running: it checks Paperless for changes every 5 minutes (Settings → Check for
changes), and opens at login unless you turn that off in Settings.

## How it works

A [File Provider](https://developer.apple.com/documentation/fileprovider) extension serves the
Finder location. Each refresh fetches the document list, builds the folder tree, and reports what
changed since the last one. Files download from `/api/documents/{id}/download/`, which gives the
archived (OCR'd, searchable) PDF when Paperless made one, or the original otherwise.

Paperless has no push notifications, so changes reach Finder on the next check, or right away
with Sync Now.

## Limitations

- In offline mode a document is stored once per folder it appears in.
- Finder tags you add yourself stay on this Mac.
- A file Paperless won't take (an unsupported type, say) keeps a sync error in Finder with
  Paperless's reason. Delete it there.
- A file Paperless accepts but then fails to consume stays in place with "(upload failed)" in its
  name. Check the file tasks page in Paperless for the reason, then delete the file.

## Development

```bash
make build    # xcodegen + xcodebuild
make test     # unit tests for the folder tree, in Packages/PaperlessCore
make lint     # swift format, as CI runs it
make format
```

- `App/`: the menu bar app (settings, login, refresh timer)
- `Extension/`: the File Provider extension
- `Packages/PaperlessCore/`: the Paperless API client, the folder tree and config, shared by both

`project.yml` generates the Xcode project, so edit that rather than the `.xcodeproj`.

## License

MIT, except the leaf in the app icon (`App/AppIcon.icon/Assets/leaf.svg`), which is the
Paperless-ngx logo under that project's GPL-3.0 licence. Paperless Desktop isn't affiliated with
Paperless-ngx.
