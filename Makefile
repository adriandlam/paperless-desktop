# Needs Xcode 16+ and xcodegen (brew install xcodegen).
APP := build/Build/Products/Debug/PaperlessDesktop.app
SOURCES := App Extension Packages/PaperlessCore/Sources Packages/PaperlessCore/Tests

.PHONY: build install test lint format clean

build:
	xcodegen generate --quiet
	xcodebuild -scheme PaperlessDesktop -derivedDataPath build -allowProvisioningUpdates -quiet build

# Replaces the installed copy and restarts both the app and the Finder extension.
install: build
	-osascript -e 'quit app "PaperlessDesktop"'
	-pkill -x PaperlessFileProvider
	ditto $(APP) /Applications/PaperlessDesktop.app
	open /Applications/PaperlessDesktop.app

test:
	swift test --package-path Packages/PaperlessCore

lint:
	swift format lint --strict --recursive $(SOURCES)

format:
	swift format --in-place --recursive $(SOURCES)

clean:
	rm -rf build PaperlessDesktop.xcodeproj
