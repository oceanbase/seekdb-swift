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

XCODE ?= /Applications/Xcode.app/Contents/Developer
SIM ?= iPhone 17
BUNDLE_ID := org.seekdb.shell
DERIVED := build
APP := $(DERIVED)/Build/Products/Debug-iphonesimulator/SeekDBShell.app
XCB := DEVELOPER_DIR=$(XCODE) xcodebuild -project SeekDBShell.xcodeproj -scheme SeekDBShell -derivedDataPath $(DERIVED)
SIMCTL := DEVELOPER_DIR=$(XCODE) xcrun simctl
ARGS ?=

.PHONY: project build run boot install launch test ui-test screenshot clean

project:
	xcodegen generate --quiet

build: project
	$(XCB) -destination 'platform=iOS Simulator,name=$(SIM)' build -quiet

boot:
	-$(SIMCTL) boot '$(SIM)' 2>/dev/null
	open "$(XCODE)/../Applications/DeviceHub.app" 2>/dev/null || open "$(XCODE)/Applications/Simulator.app"

install: build boot
	$(SIMCTL) install '$(SIM)' $(APP)

launch:
	-$(SIMCTL) terminate '$(SIM)' $(BUNDLE_ID) 2>/dev/null
	$(SIMCTL) launch '$(SIM)' $(BUNDLE_ID) $(ARGS)

run: install launch

test:
	cd Packages/ShellCore && DEVELOPER_DIR=$(XCODE) swift test

ui-test: project
	rm -rf $(DERIVED)/UITests.xcresult $(DERIVED)/UITests
	$(XCB) -destination 'platform=iOS Simulator,name=$(SIM)' -resultBundlePath $(DERIVED)/UITests.xcresult test -quiet
	DEVELOPER_DIR=$(XCODE) xcrun xcresulttool export attachments --path $(DERIVED)/UITests.xcresult --output-path $(DERIVED)/UITests

screenshot:
	mkdir -p $(DERIVED)
	$(SIMCTL) io '$(SIM)' screenshot $(or $(OUT),$(DERIVED)/screenshot.png)

clean:
	rm -rf $(DERIVED) SeekDBShell.xcodeproj
