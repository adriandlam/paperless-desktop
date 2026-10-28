# Paperless Desktop

Puts a Paperless-ngx library in Finder's sidebar, read-only: folders by
correspondent, tag, document type and year. Files download when opened;
right-click → Keep Downloaded keeps them offline. A menu bar app checks
Paperless for changes every 5 minutes.

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme PaperlessDesktop -derivedDataPath build build
ditto build/Build/Products/Debug/PaperlessDesktop.app /Applications/PaperlessDesktop.app
open /Applications/PaperlessDesktop.app
```

Then log in with your Paperless username and password (only the API token they
unlock is saved), or paste a token from My Profile → API Auth Token.

Tests for the folder tree: `cd Packages/PaperlessCore && swift test`.
