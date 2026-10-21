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

public enum OutputFormatter {
    public static func render(
        _ results: [QueryResult], statement: String, elapsed: Duration, vertical: Bool = false, maxRows: Int = 1000
    ) -> String {
        let time = seconds(elapsed)
        guard !results.isEmpty else { return "Query OK (\(time))\n\n" }
        return results
            .map { render($0, statement: statement, time: time, vertical: vertical, maxRows: maxRows) }
            .joined()
    }

    public static func render(error: QueryError) -> String {
        switch (error.code, error.sqlState) {
        case let (code?, state?):
            return "ERROR \(code) (\(state)): \(error.message)\n"
        case let (code?, nil):
            return "ERROR \(code): \(error.message)\n"
        default:
            return "ERROR: \(error.message)\n"
        }
    }

    public static func table(columns: [Column], rows: [[String?]]) -> String {
        let header = columns.map { escape($0.name) }
        let cells = rows.map { row in
            columns.indices.map { index in
                index < row.count ? row[index].map(escape) ?? "NULL" : "NULL"
            }
        }
        var widths = header.map(\.terminalWidth)
        for row in cells {
            for (index, cell) in row.enumerated() {
                widths[index] = max(widths[index], cell.terminalWidth)
            }
        }
        let border = "+" + widths.map { String(repeating: "-", count: $0 + 2) }.joined(separator: "+") + "+"
        var lines = [border, line(header, widths: widths, rightAligned: columns.map { _ in false }), border]
        lines += cells.map { line($0, widths: widths, rightAligned: columns.map(\.isNumeric)) }
        lines.append(border)
        return lines.joined(separator: "\n")
    }

    public static func vertical(columns: [Column], rows: [[String?]]) -> String {
        let width = columns.map(\.name.terminalWidth).max() ?? 0
        let stars = String(repeating: "*", count: 27)
        var lines: [String] = []
        for (number, row) in rows.enumerated() {
            lines.append("\(stars) \(number + 1). row \(stars)")
            for (index, column) in columns.enumerated() {
                let value = index < row.count ? row[index] ?? "NULL" : "NULL"
                lines.append(String(repeating: " ", count: width - column.name.terminalWidth) + column.name + ": " + value)
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func seconds(_ elapsed: Duration) -> String {
        let (seconds, attoseconds) = elapsed.components
        return String(format: "%.2f sec", Double(seconds) + Double(attoseconds) / 1e18)
    }

    private static func render(_ result: QueryResult, statement: String, time: String, vertical: Bool, maxRows: Int) -> String {
        switch result {
        case let .rows(columns, rows):
            guard !rows.isEmpty else { return "Empty set (\(time))\n\n" }
            let shown = Array(rows.prefix(maxRows))
            var summary = "\(rows.count) \(rows.count == 1 ? "row" : "rows") in set (\(time))"
            if shown.count < rows.count {
                summary += "; showing the first \(shown.count)"
            }
            let body = vertical ? Self.vertical(columns: columns, rows: shown) : table(columns: columns, rows: shown)
            return body + "\n" + summary + "\n\n"
        case let .ok(affectedRows, warnings, info):
            if isUse(statement) {
                return "Database changed\n"
            }
            var summary = "Query OK, \(affectedRows) \(affectedRows == 1 ? "row" : "rows") affected"
            if warnings > 0 {
                summary += ", \(warnings) \(warnings == 1 ? "warning" : "warnings")"
            }
            summary += " (\(time))\n"
            return summary + (info.isEmpty ? "" : info + "\n") + "\n"
        }
    }

    private static func line(_ cells: [String], widths: [Int], rightAligned: [Bool]) -> String {
        let padded = cells.indices.map { index -> String in
            let padding = String(repeating: " ", count: widths[index] - cells[index].terminalWidth)
            return rightAligned[index] ? padding + cells[index] : cells[index] + padding
        }
        return "| " + padded.joined(separator: " | ") + " |"
    }

    private static func escape(_ value: String) -> String {
        var result = ""
        for character in value {
            switch character {
            case "\r\n": result += "\\r\\n"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\0": result += "\\0"
            default: result.append(character)
            }
        }
        return result
    }

    private static func isUse(_ statement: String) -> Bool {
        statement.range(of: #"^use\s"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
