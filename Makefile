# `make <target>` is this repo's `npm run <script>`. Everything works without
# Xcode open; run targets stay in the foreground so ⌃C stops them.

DERIVED  := DerivedData
PROJECT  := app/TeleportBread.xcodeproj
SIM      ?= iPhone 17 Pro
MAC_APP  := $(DERIVED)/Build/Products/Debug/TeleportBread.app
IOS_APP  := $(DERIVED)/Build/Products/Debug-iphonesimulator/TeleportBread.app
XCODEBUILD := xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED) -configuration Debug -quiet

.DEFAULT_GOAL := help
.PHONY: help gen build-mac mac mac-preview build-ios ios test test-mac test-ios snapshots clean

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{ printf "  \033[1m%-12s\033[0m %s\n", $$1, $$2 }'

gen: ## regenerate the Xcode project from app/project.yml (picks up new files)
	@cd app && xcodegen generate -q

build-mac: gen ## build the Mac app
	@$(XCODEBUILD) -scheme TeleportBreadMac -destination "platform=macOS,arch=arm64" build

mac: build-mac ## build + run the Mac app on your real Reminders (⌃C quits)
	@exec $(MAC_APP)/Contents/MacOS/TeleportBread

mac-preview: build-mac ## build + run the Mac app on in-memory sample data (⌃C quits)
	@TELEPORTBREAD_PREVIEW=1 exec $(MAC_APP)/Contents/MacOS/TeleportBread

build-ios: gen ## build the iOS app for the simulator (SIM="iPhone 17 Pro" by default)
	@$(XCODEBUILD) -scheme TeleportBread -destination "platform=iOS Simulator,name=$(SIM)" build

ios: build-ios ## build + run on the simulator, app log in this terminal (⌃C quits the app)
	@scripts/ios-run.sh "$(SIM)" $(IOS_APP)

test: ## InboxCore unit tests
	@cd packages/InboxCore && swift test

test-mac: gen ## Mac UI tests (creates and settles real reminders)
	@$(XCODEBUILD) -scheme TeleportBreadMac -destination "platform=macOS,arch=arm64" test

test-ios: gen ## iOS UI tests on the simulator
	@$(XCODEBUILD) -scheme TeleportBread -destination "platform=iOS Simulator,name=$(SIM)" test

snapshots: build-mac ## render the Mac UI states to /tmp/teleportbread-snapshots/*.png (headless)
	@TELEPORTBREAD_PREVIEW=1 TELEPORTBREAD_SNAPSHOT_DIR=/tmp/teleportbread-snapshots $(MAC_APP)/Contents/MacOS/TeleportBread 2>/dev/null; \
	echo "→ /tmp/teleportbread-snapshots"; ls /tmp/teleportbread-snapshots

clean: ## drop build products
	@rm -rf $(DERIVED)
