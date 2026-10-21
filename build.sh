#!/usr/bin/env bash
# Copyright (c) 2025 OceanBase.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
seekdb=${SEEKDB_DIR:?Set SEEKDB_DIR to an oceanbase/seekdb checkout where SeekDB.framework is built, as Build in README.md describes}
output="$here/build/SeekDBEngine.xcframework"
derived="$here/.build/xcode"

frameworks=()
destinations=()
for slice in "IOS:iOS:build_ios/bin/src/observer build/bin/src/observer build_ios_release" \
  "IOSSIMULATOR:iOS Simulator:build_ios_simulator/bin/src/observer build/bin/src/observer build_ios_simulator_release"; do
  IFS=: read -r expected destination directories <<<"$slice"
  for directory in $directories; do
    framework="$seekdb/$directory/framework/SeekDB.framework"
    if [[ ! -d "$framework" ]]; then
      continue
    fi
    platform=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["platform"])' \
      "$framework/build-manifest.json")
    if [[ "$platform" == "$expected" ]]; then
      echo "Packaging $framework"
      frameworks+=(-framework "$framework")
      destinations+=("generic/platform=$destination")
      break
    fi
    if [[ "$directory" != build/bin/src/observer ]]; then
      echo "$framework is built for $platform, expected $expected" >&2
      exit 1
    fi
  done
done
if [[ ${#frameworks[@]} -eq 0 ]]; then
  echo "No SeekDB.framework in $seekdb; build it there first, as Build in README.md describes" >&2
  exit 1
fi
mkdir -p "$here/build"
rm -rf "$output"
xcodebuild -create-xcframework "${frameworks[@]}" -output "$output"

if [[ ${BUILD_SWIFT_PACKAGE:-0} == 1 ]]; then
  for destination in "${destinations[@]}"; do
    (cd "$here" && xcodebuild -scheme seekdb-swift -destination "$destination" \
      -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO build)
  done
fi
