# GitFork

GitFork is a macOS-native Git GUI inspired by the clarity and three-column workflow of
[Fork](https://git-fork.com/). It is written entirely in Swift and SwiftUI and talks to
the Git installation built into macOS at `/usr/bin/git`.

## Features

- Open and remember local Git repositories
- Browse local branches, remote branches, tags, and all commit history
- Search commits by subject, author, hash, or reference
- Inspect syntax-colored commit and working-tree diffs
- Stage or unstage individual files and all changes
- Commit and amend from the changes view
- Fetch, fast-forward pull, and push
- Create and check out branches
- Stash tracked and untracked changes
- Install a `fork` command-line helper from the GitFork application menu
- Native macOS menus, keyboard shortcuts, sheets, toolbar, sidebar, and dark mode

## Requirements

- macOS 14 or later
- Xcode 16 or later
- Git available at `/usr/bin/git`

## Run

```sh
swift run GitFork
```

## Build a macOS app bundle

```sh
make app
open .build/release/GitFork.app
```

The local build is ad-hoc signed. Distribution outside your Mac requires an Apple
Developer ID certificate and notarization.

## Command-line helper

Choose **GitFork → Install Command Line Tool…** from the macOS application menu.
The installer defaults to `/usr/local/bin` and also offers `/opt/homebrew/bin`,
`~/.local/bin`, or a custom absolute directory.

If the directory is not writable, macOS presents an administrator authorization
prompt. GitFork asks for confirmation before replacing a different executable
named `fork`.

Once installed, run the helper from anywhere inside a Git repository:

```sh
fork
fork open
fork open /path/to/repository
fork --help
fork --version
```

The helper discovers the repository root and launches GitFork through its
`gitfork://` URL handler.

## Test

```sh
swift test
```
