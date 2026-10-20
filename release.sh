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
version=${1:?Usage: release.sh VERSION}
repository=${RELEASE_REPOSITORY:-oceanbase/seekdb-swift}
framework="$here/build/SeekDBEngine.xcframework"
archive="$here/build/release/$version/SeekDBEngine.xcframework.zip"
manifest="$here/Package.swift"

for slice in ios-arm64 ios-arm64-simulator; do
  if [[ ! -d "$framework/$slice/SeekDB.framework" ]]; then
    echo "$framework has no $slice slice; package the device and Simulator frameworks with build.sh first" >&2
    exit 1
  fi
done
provenance=$(python3 - "$framework" <<'EOF'
import json
import sys

manifests = [json.load(open("%s/%s/SeekDB.framework/build-manifest.json" % (sys.argv[1], slice)))
             for slice in ("ios-arm64", "ios-arm64-simulator")]
revisions = sorted({manifest["source_revision"] for manifest in manifests})
if len(revisions) != 1:
    sys.exit("The device and Simulator slices come from different seekdb revisions: " + ", ".join(revisions))
print(revisions[0], int(any(manifest["source_dirty"] for manifest in manifests)))
EOF
)
read -r revision dirty <<<"$provenance"
if [[ $dirty == 1 ]]; then
  if [[ ${ALLOW_DIRTY:-0} != 1 ]]; then
    echo "SeekDB.framework was built from seekdb $revision with uncommitted changes; rebuild it from a clean tree, or set ALLOW_DIRTY=1 for a trial run" >&2
    exit 1
  fi
  echo "warning: SeekDB.framework was built from seekdb $revision with uncommitted changes; do not publish this archive" >&2
fi
for name in releasedEngine releasedEngineChecksum; do
  if [[ $(grep -c "^let $name = \"" "$manifest") != 1 ]]; then
    echo "$manifest must define $name exactly once" >&2
    exit 1
  fi
done

rm -rf "$(dirname "$archive")"
mkdir -p "$(dirname "$archive")"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$framework" "$archive"
checksum=$(swift package compute-checksum "$archive")
url="https://github.com/$repository/releases/download/$version/SeekDBEngine.xcframework.zip"

sed -i.orig -e "s|^let releasedEngine = \".*\"\$|let releasedEngine = \"$url\"|" \
  -e "s|^let releasedEngineChecksum = \".*\"\$|let releasedEngineChecksum = \"$checksum\"|" "$manifest"
rm -f "$manifest.orig"

cat <<EOF
Prepared $repository $version from seekdb $revision
  archive:  $archive
  checksum: $checksum
Package.swift now names that archive in the $version release. Review it, then publish:
  git -C $here commit -m "seekdb-swift $version" Package.swift
  git -C $here push
  gh release create $version $archive --repo $repository --target "\$(git -C $here rev-parse HEAD)" --title $version --notes "Engine built from seekdb $revision."
EOF
