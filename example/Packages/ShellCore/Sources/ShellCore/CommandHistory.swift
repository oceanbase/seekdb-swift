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

import Foundation

public struct CommandHistory: Equatable, Sendable {
    public private(set) var entries: [String]
    public let limit: Int
    private var cursor: Int?
    private var draft = ""

    public init(entries: [String] = [], limit: Int = 200) {
        self.entries = Array(entries.suffix(limit))
        self.limit = limit
    }

    public mutating func record(_ command: String) {
        cursor = nil
        draft = ""
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, entries.last != trimmed else { return }
        entries.append(trimmed)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    public mutating func older(than current: String) -> String? {
        guard !entries.isEmpty else { return nil }
        let position: Int
        if let cursor {
            guard cursor > 0 else { return nil }
            position = cursor - 1
        } else {
            draft = current
            position = entries.count - 1
        }
        cursor = position
        return entries[position]
    }

    public mutating func newer() -> String? {
        guard let cursor else { return nil }
        if cursor + 1 < entries.count {
            self.cursor = cursor + 1
            return entries[cursor + 1]
        }
        self.cursor = nil
        return draft
    }
}
