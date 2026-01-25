SWIFT_FORMAT ?= swift-format
XCODEGEN ?= xcodegen

GIT_SHA ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "")
GIT_TAG ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "")
GIT_BUILD_ID ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "")
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo "1")

# Use the latest tag (optionally prefixed with 'v') as the app version.
APP_VERSION ?= $(shell \
	if [ -n "$(GIT_TAG)" ]; then echo "$(GIT_TAG)" | sed -E 's/^v//'; else echo "0.1.0"; fi \
)

.PHONY: format lint test build build-ci build-universal-ci resolve clean xcodegen

.PHONY: dmg

xcodegen:
	cd App && $(XCODEGEN) generate

format:
	@$(SWIFT_FORMAT) format -i -r Package.swift Sources Tests

lint:
	@$(SWIFT_FORMAT) lint --strict -r Package.swift Sources Tests

build:
	xcodebuild \
		-project App/PodcastTransfer.xcodeproj \
		-scheme PodcastTransfer \
		-configuration Debug \
		-destination 'platform=macOS' \
		MARKETING_VERSION="$(APP_VERSION)" \
		CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		INFOPLIST_KEY_PodcastTransferGitSHA="$(GIT_SHA)" \
		INFOPLIST_KEY_PodcastTransferGitTag="$(GIT_TAG)" \
		INFOPLIST_KEY_PodcastTransferBuildIdentifier="$(GIT_BUILD_ID)" \
		build

build-ci:
	xcodebuild \
		-project App/PodcastTransfer.xcodeproj \
		-scheme PodcastTransfer \
		-configuration Debug \
		-destination 'platform=macOS' \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGN_IDENTITY="" \
		MARKETING_VERSION="$(APP_VERSION)" \
		CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		INFOPLIST_KEY_PodcastTransferGitSHA="$(GIT_SHA)" \
		INFOPLIST_KEY_PodcastTransferGitTag="$(GIT_TAG)" \
		INFOPLIST_KEY_PodcastTransferBuildIdentifier="$(GIT_BUILD_ID)" \
		build

build-universal-ci:
	xcodebuild \
		-project App/PodcastTransfer.xcodeproj \
		-scheme PodcastTransfer \
		-configuration Release \
		-destination 'platform=macOS' \
		ARCHS="arm64 x86_64" \
		ONLY_ACTIVE_ARCH=NO \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGN_IDENTITY="" \
		MARKETING_VERSION="$(APP_VERSION)" \
		CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		INFOPLIST_KEY_PodcastTransferGitSHA="$(GIT_SHA)" \
		INFOPLIST_KEY_PodcastTransferGitTag="$(GIT_TAG)" \
		INFOPLIST_KEY_PodcastTransferBuildIdentifier="$(GIT_BUILD_ID)" \
		build

test:
	swift test -v

resolve:
	swift package resolve

clean:
	swift package clean

dmg:
	@set -euo pipefail; \
	APP_PATH="$${APP_PATH:-}"; \
	if [[ -z "$$APP_PATH" ]]; then \
		APP_PATH=$$(find ~/Library/Developer/Xcode/DerivedData \
			\( \
				-path "*/Build/Products/Release/Podcast Transfer.app" -o \
				-path "*/Build/Products/Release/PodcastTransfer.app" -o \
				-path "*/Build/Products/Debug/Podcast Transfer.app" -o \
				-path "*/Build/Products/Debug/PodcastTransfer.app" \
			\) \
			-print -quit || true); \
	fi; \
	if [[ -z "$$APP_PATH" ]]; then \
		echo "APP_PATH is not set and no built app was found in DerivedData." >&2; \
		echo "Build one first (e.g. make build or make build-universal-ci), then re-run: make dmg" >&2; \
		exit 1; \
	fi; \
	bash Scripts/create_dmg.sh --app-path "$$APP_PATH" --output "PodcastTransfer.dmg"
