SWIFT_FORMAT ?= swift-format
XCODEGEN ?= xcodegen

GIT_SHA ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "")
GIT_TAG ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo "")
GIT_BUILD_ID ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "")
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo "1")

# Optional signing settings (primarily for CI/release builds). When provided, they are
# forwarded to xcodebuild.
XCODEBUILD_SIGNING_ARGS :=
ifdef CODE_SIGN_IDENTITY
XCODEBUILD_SIGNING_ARGS += CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)"
endif
ifdef DEVELOPMENT_TEAM
XCODEBUILD_SIGNING_ARGS += DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)"
endif

# Use the latest tag (optionally prefixed with 'v') as the app version.
APP_VERSION ?= $(shell \
	if [ -n "$(GIT_TAG)" ]; then echo "$(GIT_TAG)" | sed -E 's/^v//'; else echo "0.1.0"; fi \
)

.PHONY: format lint test build build-universal resolve clean xcodegen

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

build-universal:
	xcodebuild \
		-project App/PodcastTransfer.xcodeproj \
		-scheme PodcastTransfer \
		-configuration Release \
		-destination 'platform=macOS' \
		ARCHS="arm64 x86_64" \
		ONLY_ACTIVE_ARCH=NO \
		MARKETING_VERSION="$(APP_VERSION)" \
		CURRENT_PROJECT_VERSION="$(BUILD_NUMBER)" \
		INFOPLIST_KEY_PodcastTransferGitSHA="$(GIT_SHA)" \
		INFOPLIST_KEY_PodcastTransferGitTag="$(GIT_TAG)" \
		INFOPLIST_KEY_PodcastTransferBuildIdentifier="$(GIT_BUILD_ID)" \
		$(XCODEBUILD_SIGNING_ARGS) \
		build

test:
	swift test -v

resolve:
	swift package resolve

clean:
	swift package clean
