// Copyright (c) 2025 OceanBase.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Testing
@testable import ShellCore

struct CommandHistoryTests {
    @Test func recordsTrimmedCommandsWithoutRepeats() {
        var history = CommandHistory()
        history.record(" select 1; ")
        history.record("select 1;")
        history.record("   ")
        history.record("select 2;")
        #expect(history.entries == ["select 1;", "select 2;"])
    }

    @Test func walksBackAndForthAndRestoresTheDraft() {
        var history = CommandHistory(entries: ["a", "b"])
        #expect(history.older(than: "draft") == "b")
        #expect(history.older(than: "b") == "a")
        #expect(history.older(than: "a") == nil)
        #expect(history.newer() == "b")
        #expect(history.newer() == "draft")
        #expect(history.newer() == nil)
    }

    @Test func keepsOnlyTheNewestEntries() {
        var history = CommandHistory(entries: ["a", "b"], limit: 2)
        history.record("c")
        #expect(history.entries == ["b", "c"])
    }
}
