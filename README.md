# SeekDB Swift bindings

`Sources/SeekDB` contains the API (`SeekDB`, `ConnectionOptions`, `SeekDBError`).
It runs seekdb in process: `NativeAPI.swift` calls the lifecycle functions of
oceanbase/seekdb's `SeekDB.framework` through the `CSeekDB` module, and the framework
runs the engine inside the application on a dedicated 8 MiB-stack thread. An iOS app
cannot start the separate SeekDB process that libseekdb launches on desktop systems
and Android. The API follows the Java bindings. It has no third-party Swift
dependencies and does not include a SQL client, construct connection URLs, execute
queries, or decode result sets. Applications choose and configure their own
MySQL-protocol client; the [iOS example App](example/README.md) uses MySQLNIO.

## Package layout

This repository is a SwiftPM package: `Package.swift` exposes the `SeekDB` library
from `Sources/SeekDB`. The engine is seekdb's `SeekDB.framework`, which `build.sh`
packages as `build/SeekDBEngine.xcframework` (see [Build](#build)). When that exists
as SwiftPM resolves the package, the package uses it as the binary target
`SeekDBEngine`; otherwise SwiftPM downloads the engine that `Package.swift` names in
`releasedEngine` and `releasedEngineChecksum` from a release of this repository and
checks its checksum; `release.sh` writes both. SwiftPM caches that choice, and
[Build](#build) says when to clear it. Both hold iOS slices only for now.

`CSeekDB` is a module map whose `shim.h` includes the framework's own
`<SeekDB/seekdb.h>`. That header comes from seekdb's
`rust/in-process/include/seekdb.h` (`src/observer/in_process/seekdb.h` in the seekdb
revision that release 0.1.0's engine was built from) and declares `seekdb_open`,
`seekdb_last_open_error`, `seekdb_close` and `seekdb_connection_options`.
seekdb-bindings' `lib/include/seekdb/seekdb.h` belongs to the out-of-process
`libseekdb` and is not used here.

`NativeAPI.swift` imports `CSeekDB` with `@_implementationOnly`. With a plain or
`internal import`, every module that imports `SeekDB` must also find the `CSeekDB`
module map, because clients of a module built without library evolution load its
imports, and compiling without it fails with "missing required module 'CSeekDB'".
The `SeekDB` target enables the experimental feature `CheckImplementationOnly`, which
makes storing a `CSeekDB` type in a property a compile error rather than a warning:
clients would compute such a type's layout without seeing `CSeekDB`.

```swift
// In a consuming package's Package.swift:
dependencies: [
    .package(url: "https://github.com/oceanbase/seekdb-swift.git", from: "0.1.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "SeekDB", package: "seekdb-swift")
    ])
]
```

In Xcode, add `https://github.com/oceanbase/seekdb-swift` with File > Add Package
Dependencies. Inside seekdb-bindings this package is the `swift/` submodule; added by
path (`.package(path: "../seekdb-bindings/swift")`), SwiftPM names it after its
directory, so the product is `.product(name: "SeekDB", package: "swift")`. A native
engine is still required, just as the Java JAR requires its matching native
components; the package downloads a released one when no local build exists, and it
does not change process search paths.

The package needs Swift 6.0 or later, that is Xcode 16 or later, and apps need iOS 18
or later. The engine has iOS slices only, so build for an iOS device or Simulator:
with My Mac as the destination, Xcode stops with "While building for macOS, no library
for this platform was found".

## Build

Requires macOS with full Xcode and the iOS SDKs. `build.sh` uses
`/Applications/Xcode.app/Contents/Developer` unless `DEVELOPER_DIR` is set.

The in-process engine comes from
[oceanbase/seekdb#1514](https://github.com/oceanbase/seekdb/pull/1514), which is to be
rebased onto seekdb's Bazel build and merged into `master`. With the Bazel build,
build the framework in a seekdb checkout and package it here:

```sh
cd /path/to/seekdb
./build.py init --ios
./build.py build -o build_ios --config=ios seekdb                        # device
./build.py init --ios --simulator
./build.py build -o build_ios_simulator --config=ios-simulator seekdb    # Simulator
cd /path/to/seekdb-swift
SEEKDB_DIR=/path/to/seekdb bash build.sh
```

Until then, the pull request's branch, `feature/in-process-embedded-mode`, builds the
framework with CMake instead; `build.sh` packages it the same way:

```sh
./build.sh release --ios --framework --init --make -j8               # device
./build.sh release --ios --simulator --framework --init --make -j8   # Simulator
```

`build.sh` puts each `SeekDB.framework` it finds in `SEEKDB_DIR` (device, Simulator
or both) into `build/SeekDBEngine.xcframework`, after checking the platform that each
framework's `build-manifest.json` names. For each platform it takes the first
framework it finds under `build_ios/bin/src/observer` or
`build_ios_simulator/bin/src/observer` (Bazel with `-o`), `build/bin/src/observer`
(Bazel without `-o`, which keeps only the platform built last) and
`build_ios_release` or `build_ios_simulator_release` (CMake), each followed by
`framework/SeekDB.framework`. `BUILD_SWIFT_PACKAGE=1` also builds this package with
`xcodebuild` for each packaged platform; its intermediate files go to `.build/xcode`.

SwiftPM caches what `Package.swift` returns by the file's contents, not by whether
`build/SeekDBEngine.xcframework` exists. A package that Xcode or SwiftPM resolved
before `build.sh` created that directory keeps using the released engine, and one
resolved while it existed fails after it is deleted, with "local binary target
'SeekDBEngine' at '.../build/SeekDBEngine.xcframework' does not contain a binary
artifact". Delete `~/Library/Caches/org.swift.swiftpm/manifests` after creating or
deleting the directory.

## API

```swift
import SeekDB

// Run this work away from the UI thread: open and close are synchronous.
let db = try SeekDB.open("/absolute/writable/persistent/database")
defer { try? db.close() }

let options = try db.connectionOptions()
// Configure your chosen client using options.transport and its endpoint fields.
// Execute SQL and close all client connections before closing db.

try db.close()
```

`ConnectionOptions` is a copied, immutable, `Sendable` value with fields matching
the C and Java APIs: `transport`, `port`, `host`, `unix_socket`, `named_pipe`, and
`user`. Unused strings remain `nil`; local endpoints have port zero. The snapshot
does not extend the native handle's lifetime. Do not open client connections from
saved options after the owning instance closes.

`SeekDB.open(path, parameters: ["memory_budget", "2G", "log_disk_size", "4G"])`
passes alternating key/value strings to `seekdb_open`. The wrapper rejects
odd-length lists, empty names, and embedded NUL bytes. Other values are validated
by the native implementation. Native open errors retain their return code and
same-thread diagnostic in `SeekDBError`.

Options and close operations on a handle are serialized. A successful close is
idempotent, and options requested afterward throw `SeekDBError.closed`. Failed
close retains the handle. `deinit` attempts best-effort cleanup, but explicit close
is required to observe failures.

## Runtime constraints

Xcode embeds and signs `SeekDB.framework` with an app that depends on `SeekDB`. Apps
that call the C API directly can embed the framework and include its
`Headers/seekdb.h`.

- iOS 18 or newer. Device and Simulator frameworks are separate slices.
- The first open starts the engine, which keeps running until the process exits;
  close only releases the handle. Opening the same directory again reuses the
  running engine, also after every handle has been closed. Another directory is
  rejected, and so is any open after the engine failed to start;
  `seekdb_last_open_error` says why.
- A new database defaults to `memory_budget=1G`, `vector_memory_limit=128M`,
  `log_disk_size=2G` and `datafile_maxsize=20G`; parameters override them when the
  database is created. TCP is not available: a non-zero `port`, or a
  `mysql_port_mode` other than `disabled`, is rejected.
- Open returns once the engine runs and its Unix socket sends a MySQL handshake.
  The connection options carry `transport` `unix_socket`, the socket path in
  `unix_socket` (a short alias under the App's tmp directory, or under `/tmp` on
  the Simulator, when the real path is too long) and `user` `root`, with an empty
  password.
- The engine sets the process working directory to its data directory and leaves
  it there, so use absolute paths. The first open blocks until the engine accepts
  connections; call it away from the UI thread.

## Validation

Validated on 2026-10-15 with macOS 27.0, Xcode 27.0, Swift 6.4 and the iOS 27.0
SDK, against Device and Simulator frameworks built from seekdb `9786f15d9` (branch
`feature/ios-swift`, 4 exports), with the package reading the framework's own
header: `build.sh` packaged both and built the package for each with
`BUILD_SWIFT_PACKAGE=1`. On an iPhone 17 Simulator with iOS 27.0, a separate Swift
package that depends on this one by local path opened the engine through the
`SeekDB` product, read its connection options and closed it, and its process did not
crash when it exited with the engine still running. The Device framework was built
and verified but not run on a device.

On 2026-10-21, with Xcode 26.6 (iOS 26.5 SDK), Swift tools version 6.0 and macOS's
bash 3.2, `build.sh` packaged three layouts:
- release 0.1.0's slices, placed as the CMake build places them;
- the Simulator framework from a Bazel build of seekdb `b24ba7648`, together with
  release 0.1.0's device slice under a manifest rewritten to match it, placed as
  `-o build_ios` and `-o build_ios_simulator` place them;
- that Bazel checkout itself, whose `build` held only the Simulator framework.

With `BUILD_SWIFT_PACKAGE=1`, the package built for iOS and the iOS Simulator from the
first two layouts. A trial `release.sh 0.1.1` worked on both, and warned for the Bazel
manifests. The SwiftPM cache behaviour described under [Build](#build) was observed
the same day.

## Release

`release.sh VERSION` prepares a release of this package in this repository,
[oceanbase/seekdb-swift](https://github.com/oceanbase/seekdb-swift), the repository
that apps add by URL. Package the device and Simulator frameworks with `build.sh` from
a clean seekdb tree first, then, in a clone of this repository:

```sh
git clone https://github.com/oceanbase/seekdb-swift.git ~/seekdb-swift
cd ~/seekdb-swift
SEEKDB_DIR=/path/to/seekdb bash build.sh
bash release.sh 0.2.0
```

It checks that both slices come from the same seekdb revision built without
uncommitted changes (`ALLOW_DIRTY=1` allows a trial run). The Bazel build does not
record uncommitted changes, so for its frameworks `release.sh` only warns, and the
seekdb tree has to be clean when they are built. It then zips the XCFramework
without macOS `._` files into `build/release/<version>/`, computes the archive's
checksum, and writes the release asset's URL and that checksum into `releasedEngine`
and `releasedEngineChecksum` in `Package.swift`. It then prints the commit, push and
`gh release create` commands and publishes nothing itself. `gh release create` makes
the version tag on the pushed commit and uploads the archive; upload exactly the
archive it made, since the checksum belongs to that file. `RELEASE_REPOSITORY` names
another repository.

Versions stay at 0.x while the engine comes from an unreleased seekdb branch; once
a seekdb release ships the in-process runtime, the package takes that release's
version.
