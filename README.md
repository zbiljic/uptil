# UpTil

UpTil is a macOS menu bar app that keeps your Mac awake for a set time, until
a chosen time of day, or until you stop it, and then lets it sleep normally
again.

UpTil requires a Mac with Apple silicon and macOS 14 or later.

## Highlights

- Starts a session with one click: 15 minutes, 30 minutes, 1 hour, or 2 hours.
  Each further click adds time.
- Keeps the Mac awake until a time of day, or until you stop it.
- Pauses a session, letting the Mac sleep, without losing the remaining time.
- Lets the display sleep unless you turn on **Keep display awake**.
- Shows the remaining time in the menu bar.
- Includes an `uptil` command-line helper and MCP server for scripts and
  agents.

UpTil prevents only idle sleep, and only during a session. Choosing **Sleep**,
closing the lid, and system power policy still apply.

## Installation

Prebuilt [releases](https://github.com/zbiljic/uptil/releases) are being
prepared. Once published, download `UpTil-VERSION-arm64.zip`, open it, and move
`UpTil.app` to `/Applications`.

Releases are ad hoc signed and not notarized. UpTil is sandboxed, has no
network access, and asks for no permissions. If macOS blocks opening it, go to
**System Settings → Privacy & Security → Open Anyway**, then confirm **Open**
([Apple's guide](https://support.apple.com/en-us/102445)). Alternatively, if
you trust the downloaded release, remove its quarantine attribute, then open
UpTil again:

```sh
xattr -dr com.apple.quarantine /Applications/UpTil.app
```

UpTil has no Dock icon; look for `⟩˄⟨` in the menu bar. If it is missing, the
menu bar may be full, or a menu bar manager may be hiding it. To start UpTil
at login, add it in **System Settings → General → Login Items**.

## Command-line helper

The app includes an `uptil` helper that controls the running app; it does not
launch UpTil.

```sh
ln -s /Applications/UpTil.app/Contents/Helpers/uptil ~/.local/bin/uptil
uptil status --json
uptil start 45m     # start or replace a timed session
uptil extend 15m
uptil stop
```

Run `uptil help` for all commands. Durations use `s`, `m`, or `h`, such as `30s`
or `1.5h`. Unlike the app's **+** buttons, `start` replaces the current session.
`status --json` reports a `state` of `idle`, `timed`, `indefinite`, `paused`,
or `unavailable`. Exit codes: 0 success, 1 error, 2 invalid or rejected, 3
UpTil not running, 4 outcome unknown (run `uptil status` before retrying).

`uptil mcp` is a stdio MCP server for protocol version `2026-07-28` with
`uptil.status`, `uptil.start`, `uptil.indefinite`, `uptil.extend`,
`uptil.shorten`, and `uptil.stop` tools:

```json
{
  "mcpServers": {
    "uptil": {
      "command": "/Applications/UpTil.app/Contents/Helpers/uptil",
      "args": ["mcp"]
    }
  }
}
```

## Development

Requirements: Xcode 26.6 or later with Swift 6.3, and
[mise](https://mise.jdx.dev/).

```sh
git clone https://github.com/zbiljic/uptil.git
cd uptil
mise install
scripts/run
```

`scripts/stop` stops the development build, and `scripts/uptil` runs its
helper. `mise tasks` lists all tasks; `mise run check` runs the full validation
gate. `Project.swift` and `Tuist.swift` are the source of truth; do not commit
the generated `.xcodeproj` or `.xcworkspace` files.

See [RELEASING.md](RELEASING.md) for live checks, packaging, and publishing
releases.

## Support

Report bugs and requests in
[GitHub issues](https://github.com/zbiljic/uptil/issues).

## License

UpTil is licensed under the [MIT License](LICENSE).
