# `make <target>` is this repo's `npm run <script>`. Everything works without
# Xcode open; run targets stay in the foreground so ⌃C stops them.

DERIVED  := DerivedData
PROJECT  := app/InboxZero.xcodeproj
SIM      ?= iPhone 17 Pro
MAC_APP  := $(DERIVED)/Build/Products/Debug/InboxZero.app
IOS_APP  := $(DERIVED)/Build/Products/Debug-iphonesimulator/InboxZero.app
XCODEBUILD := xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED) -configuration Debug -quiet

.DEFAULT_GOAL := help
.PHONY: help gen build-mac mac mac-preview build-ios ios test test-mac test-ios snapshots clean

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{ printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2 }'

gen: ## regenerate the Xcode project from app/project.yml (picks up new files)
	@cd app && xcodegen generate -q

build-mac: gen ## build the Mac app
	@$(XCODEBUILD) -scheme InboxZeroMac -destination "platform=macOS,arch=arm64" build

mac: build-mac ## build + run the Mac app on your real Reminders (⌃C quits)
	@exec $(MAC_APP)/Contents/MacOS/InboxZero

mac-preview: build-mac ## build + run the Mac app on in-memory sample data (⌃C quits)
	@INBOXZERO_PREVIEW=1 exec $(MAC_APP)/Contents/MacOS/InboxZero

build-ios: gen ## build the iOS app for the simulator (SIM="iPhone 17 Pro" by default)
	@$(XCODEBUILD) -scheme InboxZero -destination "platform=iOS Simulator,name=$(SIM)" build

ios: build-ios ## build + run on the simulator, app log in this terminal (⌃C quits the app)
	@scripts/ios-run.sh "$(SIM)" $(IOS_APP)

test: ## InboxCore unit tests
	@cd packages/InboxCore && swift test

test-mac: gen ## Mac UI tests (creates and settles real reminders)
	@$(XCODEBUILD) -scheme InboxZeroMac -destination "platform=macOS,arch=arm64" test

test-ios: gen ## iOS UI tests on the simulator
	@$(XCODEBUILD) -scheme InboxZero -destination "platform=iOS Simulator,name=$(SIM)" test

snapshots: build-mac ## render the Mac UI states to /tmp/inboxzero-snapshots/*.png (headless)
	@INBOXZERO_PREVIEW=1 INBOXZERO_SNAPSHOT_DIR=/tmp/inboxzero-snapshots $(MAC_APP)/Contents/MacOS/InboxZero 2>/dev/null; \
	echo "→ /tmp/inboxzero-snapshots"; ls /tmp/inboxzero-snapshots

clean: ## drop build products
	@rm -rf $(DERIVED)
