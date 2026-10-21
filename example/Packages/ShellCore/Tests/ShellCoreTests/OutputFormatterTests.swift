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

struct OutputFormatterTests {
    private let columns = [Column(name: "id", isNumeric: true), Column(name: "name")]

    @Test func drawsATableWithNumbersOnTheRight() {
        let table = OutputFormatter.table(columns: columns, rows: [["1", "alice"], ["10", nil]])
        #expect(table == """
        +----+-------+
        | id | name  |
        +----+-------+
        |  1 | alice |
        | 10 | NULL  |
        +----+-------+
        """)
    }

    @Test func countsWideCharactersAsTwoColumns() {
        let table = OutputFormatter.table(columns: [Column(name: "name")], rows: [["数据库"]])
        #expect(table == """
        +--------+
        | name   |
        +--------+
        | 数据库 |
        +--------+
        """)
    }

    @Test func escapesControlCharactersInCells() {
        let table = OutputFormatter.table(columns: [Column(name: "v")], rows: [["a\nb\tc"]])
        #expect(table.contains("| a\\nb\\tc |"))
    }

    @Test func printsRowsVerticallyForBackslashG() {
        let text = OutputFormatter.render([.rows(columns: columns, rows: [["1", "alice"], ["2", nil]])],
                                          statement: "select", elapsed: .zero, vertical: true)
        #expect(text == """
        *************************** 1. row ***************************
          id: 1
        name: alice
        *************************** 2. row ***************************
          id: 2
        name: NULL
        2 rows in set (0.00 sec)


        """)
    }

    @Test func endsResultSetsWithABlankLine() {
        let one = OutputFormatter.render([.rows(columns: columns, rows: [["1", "a"]])], statement: "select", elapsed: .milliseconds(1))
        #expect(one.hasSuffix("+\n1 row in set (0.00 sec)\n\n"))
        let two = OutputFormatter.render([.rows(columns: columns, rows: [["1", "a"], ["2", "b"]])], statement: "select", elapsed: .milliseconds(1234))
        #expect(two.hasSuffix("\n2 rows in set (1.23 sec)\n\n"))
        let none = OutputFormatter.render([.rows(columns: columns, rows: [])], statement: "select", elapsed: .zero)
        #expect(none == "Empty set (0.00 sec)\n\n")
    }

    @Test func limitsTheRowsShown() {
        let rows = (1...5).map { [String($0), "x"] }
        let text = OutputFormatter.render([.rows(columns: columns, rows: rows)], statement: "select", elapsed: .zero, maxRows: 2)
        #expect(text.hasSuffix("5 rows in set (0.00 sec); showing the first 2\n\n"))
        #expect(!text.contains("|  3 |"))
    }

    @Test func summarizesStatementsWithoutRows() {
        #expect(OutputFormatter.render([.ok(affectedRows: 1, warnings: 0, info: "")], statement: "insert", elapsed: .zero)
            == "Query OK, 1 row affected (0.00 sec)\n\n")
        #expect(OutputFormatter.render([.ok(affectedRows: 2, warnings: 1, info: "Records: 2  Duplicates: 0  Warnings: 1")], statement: "insert", elapsed: .zero)
            == "Query OK, 2 rows affected, 1 warning (0.00 sec)\nRecords: 2  Duplicates: 0  Warnings: 1\n\n")
        #expect(OutputFormatter.render([.ok(affectedRows: 0, warnings: 0, info: "")], statement: "USE demo", elapsed: .zero)
            == "Database changed\n")
    }

    @Test func formatsErrorsLikeTheMySQLClient() {
        #expect(OutputFormatter.render(error: QueryError(code: 1146, sqlState: "42S02", message: "Table 'test.t' doesn't exist"))
            == "ERROR 1146 (42S02): Table 'test.t' doesn't exist\n")
        #expect(OutputFormatter.render(error: QueryError(code: 2013, message: "Lost connection"))
            == "ERROR 2013: Lost connection\n")
        #expect(OutputFormatter.render(error: QueryError(message: "closed")) == "ERROR: closed\n")
    }
}
