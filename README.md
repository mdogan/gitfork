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
- Commit, amend, and optionally OpenPGP-sign from the changes view
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

Install or replace the app in `$HOME/Applications`:

```sh
make install
```

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

## Signed commits

Enable **Sign** beside **Amend** in the commit composer to create an OpenPGP-signed
commit. The preference is remembered between launches. GitFork uses Git's
configured signing key and GPG program. It automatically searches GUI-unavailable
shell paths including `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, and
standard system binary directories:

```sh
git config --global user.signingKey <key-id>
git config --global gpg.program /path/to/gpg
```

When signing is disabled, GitFork passes `--no-gpg-sign` so the per-commit option
also overrides a global `commit.gpgSign` setting.

Signed commits show a seal in the history list and a status badge in the commit
header. Hover the badge to see the signer and signing-key ID. Git may not request
a password when `gpg-agent` already has the key passphrase cached.

## Test

```sh
swift test
```
