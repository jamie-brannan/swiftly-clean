# swiftly-clean

`swiftly-clean` is a small command-line utility for deeply cleaning Xcode and Swift Package Manager build state.

It is useful when Xcode or SwiftPM gets stuck after local package changes, dependency updates, renamed modules, stale package fingerprints, or mysterious build/indexing issues.

## What it cleans

By default, `swiftly-clean` removes:

- all Xcode DerivedData  
  `~/Library/Developer/Xcode/DerivedData`

- the global SwiftPM cache  
  `~/Library/Caches/org.swift.swiftpm`

- SwiftPM security fingerprints  
  `~/Library/org.swift.swiftpm/security`

- the local `.build` folder in the current directory, if present  
  `./.build`

With `--deep`, it additionally removes the full SwiftPM user state:

```sh
~/Library/org.swift.swiftpm
```

Use `--deep` only when you want a more aggressive reset.

With `--resolve`, it searches the current directory tree for `Package.resolved` files and offers to delete them interactively. This is useful in hybrid projects or workspaces where multiple `Package.resolved` files cause conflicts, especially when dependencies point to a `branch` rather than an `exact` version.

## Installation

### 1. Clone the repository

```sh
git clone https://github.com/jamie-brannan/swiftly-clean.git
cd swiftly-clean
```

### 2. Make the script executable

```sh
chmod +x swiftly-clean.sh
```

### 3. Move it somewhere on your PATH

To make the command available from anywhere, move it to a directory on your shell `PATH` and rename it to drop the `.sh` extension:

```sh
mkdir -p "$HOME/bin"
mv swiftly-clean.sh "$HOME/bin/swiftly-clean"
```

Then make sure `~/bin` is on your `PATH`.

If you use `zsh`, which is the default shell on modern macOS, add this to `~/.zshrc`:

```sh
export PATH="$HOME/bin:$PATH"
```

Reload your shell config:

```sh
source ~/.zshrc
```

Now you should be able to run:

```sh
swiftly-clean
```

from any project directory.

## Verify installation

Run:

```sh
which swiftly-clean
```

You should see something like:

```sh
/Users/your-name/bin/swiftly-clean
```

You can also run:

```sh
swiftly-clean --help
```

to test that the command is found without deleting anything.

## Usage

Run from the root of the project or Swift package you want to clean:

```sh
swiftly-clean
```

This will ask for confirmation before deleting anything.

### Show help

```sh
swiftly-clean --help
```

### Show version

```sh
swiftly-clean --version
```

### Skip confirmation

```sh
swiftly-clean --force
```

### Deep clean

```sh
swiftly-clean --deep
```

### Deep clean without confirmation

```sh
swiftly-clean --force --deep
```

### Search and destroy Package.resolved files

```sh
swiftly-clean --resolve
```

This scans the current directory tree for all `Package.resolved` files, lists them with their paths, and then asks whether to delete all of them, select individual ones to delete, or skip entirely.

### Search and destroy Package.resolved files without confirmation

```sh
swiftly-clean --resolve --force
```

## Recommended workflow

When Xcode or SwiftPM gets into a bad state:

1. Commit or stash any work you care about.
2. Close Xcode, or let `swiftly-clean` ask to quit it.
3. From the project root, run:

```sh
swiftly-clean
```

4. Re-open your `.xcworkspace` or `.xcodeproj`.
5. Let SwiftPM resolve packages again.
6. Build the project.

## Notes

This tool intentionally performs a broad cleanup.

Deleting DerivedData means Xcode will need to rebuild project indexes and build intermediates. The next build may take longer than usual.

Deleting SwiftPM caches means package dependencies may need to be fetched and resolved again.

Deleting SwiftPM security fingerprints may cause SwiftPM or Xcode to ask you to trust package fingerprints again. That is expected.

## Uninstall

Remove the script from wherever you installed it.

For example, if you installed it to `~/bin`:

```sh
rm "$HOME/bin/swiftly-clean"
```

If you added `~/bin` to your `PATH` only for this tool and no longer need it, remove this line from your `~/.zshrc`:

```sh
export PATH="$HOME/bin:$PATH"
```
