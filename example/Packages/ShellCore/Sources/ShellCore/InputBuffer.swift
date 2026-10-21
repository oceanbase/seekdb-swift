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

public enum ClientCommand: Equatable, Sendable {
    case help
    case quit
    case status
    case use(String)
    case unknown(String)
    case unsupported(String)
    case error(String)
}

public enum InputEvent: Equatable, Sendable {
    case statement(String, vertical: Bool)
    case command(ClientCommand)
    case noQuery
}

public struct InputBuffer: Sendable {
    private enum State: Equatable, Sendable {
        case code
        case quoted(Character)
        case blockComment
    }

    private static let unsupportedCommands: Set<String> = [
        "charset", "connect", "edit", "nopager", "notee", "nowarning", "pager", "print",
        "prompt", "query_attributes", "rehash", "resetconnection", "source", "system", "tee", "warnings",
    ]

    public private(set) var delimiter = ";"
    private var pending = ""
    private var state = State.code
    private var hasCode = false

    public init() {}

    public var isEmpty: Bool {
        pending.isEmpty && state == .code
    }

    public var prompt: String {
        switch state {
        case .quoted("'"):
            return "     '> "
        case .quoted("\""):
            return "     \"> "
        case .quoted:
            return "     `> "
        case .blockComment:
            return "    /*> "
        case .code:
            return pending.isEmpty ? "seekdb> " : "     -> "
        }
    }

    public mutating func clear() {
        pending = ""
        state = .code
        hasCode = false
    }

    public mutating func feed(_ line: String) -> [InputEvent] {
        if isEmpty, let events = textCommand(line) {
            return events
        }
        var events: [InputEvent] = []
        let characters = Array(line)
        var index = 0
        scan: while index < characters.count {
            let character = characters[index]
            switch state {
            case .quoted(let quote):
                pending.append(character)
                index += 1
                if character == "\\", quote != "`", index < characters.count {
                    pending.append(characters[index])
                    index += 1
                } else if character == quote {
                    state = .code
                }
            case .blockComment:
                if character == "*", index + 1 < characters.count, characters[index + 1] == "/" {
                    pending.append("*/")
                    index += 2
                    state = .code
                } else {
                    pending.append(character)
                    index += 1
                }
            case .code:
                if Self.matches(characters, at: index, Array(delimiter)) {
                    events.append(finish(vertical: false))
                    index += delimiter.count
                    continue
                }
                if character == "\\", index + 1 < characters.count {
                    let name = characters[index + 1]
                    let rest = String(characters[(index + 2)...]).trimmingCharacters(in: .whitespaces)
                    index += 2
                    switch name {
                    case "g":
                        events.append(finish(vertical: false))
                    case "G":
                        events.append(finish(vertical: true))
                    case "c":
                        clear()
                    case "q":
                        events.append(.command(.quit))
                        break scan
                    case "h", "?":
                        events.append(.command(.help))
                    case "s":
                        events.append(.command(.status))
                    case "u":
                        events.append(.command(.use(databaseName(rest))))
                        break scan
                    case "d":
                        events += changeDelimiter(rest)
                        break scan
                    default:
                        events.append(.command(.unknown("\\\(name)")))
                    }
                    continue
                }
                switch character {
                case "'", "\"", "`":
                    state = .quoted(character)
                    hasCode = true
                    pending.append(character)
                case "#":
                    break scan
                case "-" where Self.startsDashComment(characters, at: index):
                    break scan
                case "/" where index + 1 < characters.count && characters[index + 1] == "*":
                    state = .blockComment
                    pending.append("/*")
                    index += 2
                    continue
                default:
                    if !character.isWhitespace {
                        hasCode = true
                    }
                    pending.append(character)
                }
                index += 1
            }
        }
        if hasCode || state != .code {
            pending.append("\n")
        } else {
            pending = ""
        }
        return events
    }

    private mutating func finish(vertical: Bool) -> InputEvent {
        let text = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        let hadCode = hasCode
        clear()
        return hadCode && !text.isEmpty ? .statement(text, vertical: vertical) : .noQuery
    }

    private mutating func textCommand(_ line: String) -> [InputEvent]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.split(whereSeparator: \.isWhitespace).first else { return nil }
        var word = first.lowercased()
        if word.hasSuffix(delimiter) {
            word = String(word.dropLast(delimiter.count))
        }
        let argument = String(trimmed.dropFirst(first.count)).trimmingCharacters(in: .whitespaces)
        switch word {
        case "help", "?":
            return [.command(.help)]
        case "quit", "exit":
            return [.command(.quit)]
        case "status":
            return [.command(.status)]
        case "clear":
            return []
        case "go", "ego":
            return [.noQuery]
        case "use":
            return [.command(.use(databaseName(argument)))]
        case "delimiter":
            return changeDelimiter(argument)
        default:
            return Self.unsupportedCommands.contains(word) ? [.command(.unsupported(word))] : nil
        }
    }

    private mutating func changeDelimiter(_ argument: String) -> [InputEvent] {
        guard let token = argument.split(whereSeparator: \.isWhitespace).first.map(String.init) else {
            return [.command(.error("DELIMITER must be followed by a 'delimiter' character or string"))]
        }
        guard !token.contains("\\") else {
            return [.command(.error("DELIMITER cannot contain a backslash character"))]
        }
        delimiter = token
        return []
    }

    private func databaseName(_ argument: String) -> String {
        var name = argument.trimmingCharacters(in: .whitespaces)
        if name.hasSuffix(delimiter) {
            name = String(name.dropLast(delimiter.count)).trimmingCharacters(in: .whitespaces)
        }
        if name.count >= 2, let first = name.first, first == name.last, "`'\"".contains(first) {
            name = String(name.dropFirst().dropLast())
        }
        return name
    }

    private static func matches(_ characters: [Character], at index: Int, _ token: [Character]) -> Bool {
        guard !token.isEmpty, index + token.count <= characters.count else { return false }
        return Array(characters[index..<index + token.count]) == token
    }

    private static func startsDashComment(_ characters: [Character], at index: Int) -> Bool {
        guard index + 1 < characters.count, characters[index + 1] == "-" else { return false }
        guard index + 2 < characters.count else { return true }
        return characters[index + 2].isWhitespace
    }
}
