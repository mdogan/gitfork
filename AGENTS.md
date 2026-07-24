# AGENTS.md

## Project

GitFork is a macOS-only Git GUI inspired by Fork. It is a native Swift and
SwiftUI application backed by `/usr/bin/git`.

- Minimum deployment target: macOS 14
- Package manager: Swift Package Manager
- UI: SwiftUI, with AppKit where macOS-specific integration is required
- Tests: Swift Testing
- External dependencies: none

Do not introduce JavaScript or TypeScript. Prefer Swift for all application and
tooling code. Add Rust only when there is a demonstrated systems-level need that
Swift cannot reasonably satisfy.

## Repository Layout

- `Sources/GitFork/GitForkApp.swift`: app entry point, scenes, menus, and settings
- `Sources/GitFork/RepositoryStore.swift`: `@MainActor` application state and UI
  actions
- `Sources/GitFork/GitClient.swift`: asynchronous `/usr/bin/git` process wrapper
- `Sources/GitFork/CLIInstaller.swift`: in-app `fork` helper installation UI and
  service
- `Sources/ForkCLIKit/`: command parsing, repository discovery, and app launch URL
- `Sources/ForkCLI/`: `fork` executable entry point
- `Sources/GitFork/Models.swift`: Git domain models and output parsers
- `Sources/GitFork/*View.swift`: SwiftUI screens and reusable UI
- `Tests/GitForkTests/`: parser and real-repository integration tests
- `Tests/ForkCLIKitTests/`: CLI parsing and repository discovery tests
- `Resources/Info.plist`: macOS app-bundle metadata
- `scripts/build-app.sh`: release build, app packaging, and ad-hoc signing

Keep Git process execution out of views. Views call `RepositoryStore`;
`RepositoryStore` coordinates `GitClient` and publishes state.

## Build and Test

Run commands from the repository root:

```sh
make build
make test
make app
make install
```

Useful direct commands:

```sh
swift test --disable-sandbox
./scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 .build/release/GitFork.app
```

The packaged application is written to:

```text
.build/release/GitFork.app
```

`make install` replaces `$HOME/Applications/GitFork.app` with the newly built,
signature-verified bundle.

`.build/` is generated and must not be committed.

In restricted environments, use writable Swift and Clang cache directories if
the default user cache is unavailable:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/gitfork-clang-cache \
SWIFTPM_CUSTOM_CACHE_PATH=/tmp/gitfork-swiftpm-cache \
swift test --disable-sandbox
```

## Swift Conventions

- Keep UI-facing state on `@MainActor`.
- Run blocking `Process` and pipe reads away from the main actor.
- Prefer small value types conforming to `Sendable`, `Hashable`, and
  `Identifiable` where appropriate.
- Use structured concurrency for independent Git reads.
- Surface Git failures through `GitOperationError`; do not silently discard
  failures from mutating commands.
- Preserve `LC_ALL=C` for stable, parseable Git output.
- Preserve `GIT_TERMINAL_PROMPT=0` so the GUI never hangs on a terminal prompt.
- Pass file paths after `--` in Git commands.
- Prefer NUL-delimited Git output when parsing paths so spaces and unusual
  filenames remain safe.

## UI Conventions

- Use native SwiftUI and AppKit controls and standard macOS interaction patterns.
- Use SF Symbols instead of custom raster icons when a suitable symbol exists.
- Add `.help(...)` tooltips to icon-only and compact action controls.
- Give clickable rows and compact controls a visible hover state with pressed and
  disabled feedback; tooltips alone are not sufficient affordance.
- Support light mode, dark mode, keyboard navigation, and text selection in
  commit and diff views.
- Keep the sidebar and commit-list columns bounded. Leave the detail column
  unsized in `NavigationSplitView` so it consumes remaining window width.
- A horizontally scrolling diff must still have a minimum content width equal to
  its viewport; short diffs should fill the detail pane instead of appearing as
  a narrow strip.
- A short diff must also fill the viewport height and remain aligned to
  `.topLeading`; do not allow bidirectional scrolling to center it vertically.
- Repository switching uses the persisted `recentRepositories` list. Clearly
  mark the active repository and retain an “Open Other Repository…” action.
- The `fork` helper is bundled under `Contents/Helpers` and installed from the
  application menu. Keep its `gitfork://open?path=...` contract synchronized
  with `GitForkExternalURL`.
- Use confirmation UI before adding destructive working-tree operations.

## Git Behavior

- Reads may run concurrently when they do not mutate repository state.
- Refresh repository state after every mutating operation.
- Pulls are fast-forward-only unless product behavior is deliberately changed.
- A first push may establish an upstream using the repository's first remote.
- The commit composer owns a persistent OpenPGP signing choice. Enabled commits
  use `-c gpg.format=openpgp --gpg-sign`; disabled commits use `--no-gpg-sign`
  so the UI remains authoritative over global `commit.gpgSign`.
- Resolve `gpg.openpgp.program` or `gpg.program` to an absolute executable before
  signing. GUI-launched Git processes must augment `PATH` with Homebrew and
  common user binary directories.
- Load signature state with Git's `%G?`, `%GK`, and `%GS` pretty-format fields.
  Show signed commits in history and the detail header; a cached `gpg-agent`
  passphrase means signing may legitimately complete without a prompt.
- Do not add commands that can wait for interactive terminal input.
- Never discard changes, delete branches, rewrite history, or force-push without
  an explicit user action and appropriate confirmation.
- Keep branch, remote, tag, status, log, and diff parsing covered by focused
  tests when their formats change.

## Verification Expectations

For every code change:

1. Run `git diff --check`.
2. Run `make test`.
3. Build the release app with `make app` for UI, packaging, or app-lifecycle
   changes.
4. Verify the app signature after packaging.

Add or update tests for Git parsing and command behavior. Integration tests
should create isolated repositories beneath `FileManager.default.temporaryDirectory`
and remove them after completion.

Do not commit generated build output, user-specific Xcode state, temporary
repositories, or signing credentials.
