# Paperless Desktop

Your [Paperless-ngx](https://docs.paperless-ngx.com) library in Finder, the way iCloud Drive is.

- **A Finder location** in the sidebar, with folders for All Documents, Correspondents, Tags,
  Document Types and Years. A document shows up in every folder it belongs to.
- **Downloads on open**, with thumbnails and Quick Look from Paperless's own previews.
- **Offline copies**: right-click → Keep Downloaded on any folder, or flip one switch to keep the
  whole library on this Mac.
- **Finder tags** match the document's Paperless tags.
- **Upload by drag and drop**: drop a file into any folder and Paperless consumes it. Dropping it
  into a tag, correspondent or document type folder sets that on the new document.
- **Your password is used once** to get an API token, which is kept in the Keychain.

Everything else is read-only: renaming, moving or deleting in Finder doesn't touch Paperless.

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
2. Click **Connect**. **Paperless** appears in Finder's sidebar under Locations.

The leaf in the menu bar shows when the library last synced, with Sync Now, Open in Finder and
Settings. Leave the app running: it checks
Paperless for changes every 5 minutes and starts at login.

## How it works

A [File Provider](https://developer.apple.com/documentation/fileprovider) extension serves the
Finder location. Each refresh fetches the document list, builds the folder tree, and reports what
changed since the last one. Files download from `/api/documents/{id}/download/`, which gives the
archived (OCR'd, searchable) PDF when Paperless made one, or the original otherwise.

Paperless has no push notifications, so changes reach Finder on the next refresh: within 5
minutes, or right away with Sync Now.

## Limitations

- In offline mode a document is stored once per folder it appears in.
- Finder tags you add yourself stay on this Mac.
- A file Paperless won't take (an unsupported type, say) keeps a sync error in Finder with
  Paperless's reason. Delete it there.
- A file Paperless accepts but then fails to consume stays in place with "(upload failed)" in its name; check the file
  tasks page in Paperless for the reason, then delete the file.

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
