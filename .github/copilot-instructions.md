# Repository instructions (Podcast Transfer)

## Primary guidance

- Follow the rules in the nearest `AGENTS.md` file (this repo’s authoritative agent guidance).
- Prefer `make` targets for workflows whenever available (e.g. `make build`, `make test`, `make format`, `make lint`). Only fall back to raw `swift` / `xcodebuild` commands if there is no Make target.

## Project basics

- Language: Swift (Swift 6+).
- Concurrency: prefer structured concurrency (`async/await`, actors). Avoid completion handlers/GCD unless required by an API.
- Testing: use Swift Testing (`import Testing`), not XCTest.

## Validation expectations

- Formatting: run `make format`.
- Linting: run `make lint`.
- Tests: run `make test` if present, otherwise `swift test`.
- Builds: use `make build` (the Makefile defines the preferred build command for this repo).
