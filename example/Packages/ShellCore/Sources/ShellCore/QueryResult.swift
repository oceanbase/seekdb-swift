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

public struct Column: Equatable, Sendable {
    public var name: String
    public var isNumeric: Bool

    public init(name: String, isNumeric: Bool = false) {
        self.name = name
        self.isNumeric = isNumeric
    }
}

public enum QueryResult: Equatable, Sendable {
    case rows(columns: [Column], rows: [[String?]])
    case ok(affectedRows: UInt64, warnings: UInt16, info: String)
}

public struct QueryError: Error, Equatable, Sendable {
    public var code: UInt16?
    public var sqlState: String?
    public var message: String

    public init(code: UInt16? = nil, sqlState: String? = nil, message: String) {
        self.code = code
        self.sqlState = sqlState
        self.message = message
    }
}
