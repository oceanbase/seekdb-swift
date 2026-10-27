# iOS example App

This directory is SeekDB Shell, an iOS App that uses the Swift package one directory
up the way an application would: it starts seekdb inside the App and gives it a
terminal running a `mysql`-style client. It gets the engine the way the package does:
the `build/SeekDBEngine.xcframework` that the package's `build.sh` packages from
seekdb's `SeekDB.framework` when it exists, and the released engine otherwise; the
[Swift bindings](../README.md#build) describe how to build it, and the runtime
constraints apps have to follow.

## The terminal

The whole screen is one terminal. At launch it starts the engine, shows
`$ mysql -u root` and the client's banner, and waits at the `seekdb> ` prompt.

- Type at the prompt and press Return. A statement runs when it ends with the
  delimiter (`;` by default), `\g`, or `\G` for vertical output; until then the next
  lines start with `->`, or with `'>`, `">`, `` `> `` and `/*>` inside quotes and
  comments, lined up under the `>` of `seekdb>`. Several statements on one line run in
  order.
- Client commands work as in `mysql`: `help` (`\h`), `clear` (`\c`), `delimiter`
  (`\d`), `ego` (`\G`), `go` (`\g`), `status` (`\s`), `use` (`\u`), and `quit` or
  `exit` (`\q`). After `quit` the terminal drops to a `$ ` prompt; `mysql` there
  connects again with a new connection id.
- Output follows the `mysql` client: tables with numbers on the right, `NULL`,
  `N rows in set (0.00 sec)`, `Query OK, ...`, `Database changed` and
  `ERROR 1146 (42S02): ...`. Long lines wrap as in a terminal.
- Keys: up and down recall earlier lines (the history is kept between launches),
  ^C clears the input, ^L clears the screen, and ^D at an empty `seekdb> ` prompt quits.
  A hardware keyboard sends all of them. On the software keyboard, the bar above it has
  ↑, ↓, ^C and ^L, plus `;`, `*`, quotes, parentheses and `\G`. Pinch to change the text
  size.
- The terminal turns off smart quotes and smart dashes, so `'` stays `'`.

## How it works

- `SeekDB.open` on `Library/Application Support/seekdb` starts the engine in the App
  process. The App connects to the Unix socket from `connectionOptions()` as `root`
  with [MySQLNIO](https://github.com/vapor/mysql-nio), a pure-Swift MySQL client.
- Statements go out as `COM_QUERY` through `App/QueryCommand.swift`, a `MySQLCommand`
  that reads text result sets, OK packets, errors and further result sets. MySQLNIO
  always assumes the `CLIENT_DEPRECATE_EOF` capability, which seekdb does not announce,
  so its own `simpleQuery` returns no rows from seekdb.
- MySQLNIO never asks for `CLIENT_SESSION_TRACK` but reads OK packets with the
  server's capabilities, so it reads `info` as a length-prefixed string. To a client
  without `CLIENT_SESSION_TRACK`, seekdb sends a space and then the text, with no
  length, so MySQLNIO took the space for a length of 32 and cut
  `Records: 3  Duplicates: 0  Warnings: 0` after `Warni`. `QueryCommand` decodes OK
  packets without `CLIENT_SESSION_TRACK` and trims the space.
- `Packages/ShellCore` holds what needs no engine: `InputBuffer` (the line-by-line
  input rules of the `mysql` client), `OutputFormatter`, `ClientText` and
  `CommandHistory`, with swift-testing tests. `App/TerminalTextView.swift` is the
  terminal, a `UITextView` where only the text after the last prompt can be edited, and
  `App/MySQLClient.swift` connects the two. `UITests` types statements and keys into
  the terminal through XCUITest.

## Build and run

Needs Xcode 16 or later with an iOS Simulator runtime, as the package does, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`); the
`Makefile` uses `/Applications/Xcode.app/Contents/Developer` unless `XCODE` is set. The
Xcode project is generated from `project.yml`. It depends on the package one directory
up by local path, on MySQLNIO and SwiftNIO from GitHub, and on `Packages/ShellCore`,
and it signs ad hoc for the Simulator; to run on a device, open the generated
`SeekDBShell.xcodeproj` in Xcode and choose a team. Without a local engine, the first
build downloads the released one, about 124 MB.

```sh
make run                          # generate the project, build, install and launch on the iPhone 17 Simulator
make run SIM='iPhone 17 Pro'      # another Simulator
make test                         # ShellCore tests
make ui-test                      # type into the App on the Simulator; screenshots land in build/UITests
make screenshot                   # capture the Simulator screen to build/screenshot.png
```

`make ui-test` restarts the App in the Simulator and drops and recreates a database
named `uitest`; the rest of the data is kept. Launch arguments help with testing from
the command line:

```sh
make launch ARGS="-resetData YES -runSQL $'show databases;\nstatus'"
```

- `-resetData YES` deletes the database directory before the engine starts.
- `-runSQL "<lines>"` is typed into the terminal, line by line, as soon as it is ready.

## Limitations

- The engine keeps running until the App exits, and one process can open only one
  database directory.
- The engine listens only on its Unix socket, not on TCP, so other Apps cannot connect
  to it.
- Tables count a CJK character as two columns, but iOS has no monospaced font whose
  CJK glyphs are exactly two columns wide, so the border after them can be off by part
  of a column.
- Client commands that need files or a pager (`source`, `tee`, `pager`, `system`, ...)
  are not available.
- Keys typed while a statement is running are dropped; a terminal would keep them for
  the next prompt.

## Validation

Validated on 2026-10-21 with Xcode 26.6 (iOS 26.5 SDK) on an iPhone 17 Simulator with
iOS 26.5, against the package in this repository at `46b8147` and the released 0.1.0
engine, built from seekdb `9786f15d9`. `make test` passed its 24 tests, and
`make ui-test` passed in 18 s on a fresh install, engine start included. It typed
`drop database if exists`, `create database`, `use` without a semicolon,
`create table`, an `insert` with `''` and `NULL` (with its full `Records:` line), a
two-line statement ending in `\G`, ↑ to recall a line and ^C to drop it, ^C inside an
open quote, a table with a number on the right, `quit`, `$ mysql` with a new
connection id, and ^D at the prompt. Before it moved here, the same App, then
depending on release 0.1.0 by URL, also showed Chinese text in a table,
`ERROR 1146 (42S02)`, `status`, `exit` and `$ ls`. ↓, ^L, the key bar on the software
keyboard and pinching were not tried, and the App has not been run on a device.

The App replaces the earlier example, which ran `SELECT 1` at launch and wrote the
result to `Documents/select1.json` for `run.sh` to check; git history keeps it.
