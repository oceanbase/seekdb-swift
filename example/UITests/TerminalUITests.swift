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

import XCTest

final class TerminalUITests: XCTestCase {
    private var app: XCUIApplication!
    private var terminal: XCUIElement!

    private var text: String {
        terminal.value as? String ?? ""
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        terminal = app.textViews.firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 30))
        XCTAssertTrue(wait(timeout: 240) { $0.hasSuffix("Type 'help;' or '\\h' for help. Type '\\c' to clear the current input statement.\n\nseekdb> ") }, text)
    }

    func testTypedStatementsRunLikeTheMySQLClient() throws {
        type("drop database if exists uitest;")
        XCTAssertTrue(type("create database uitest;").contains("Query OK, 1 row affected"))
        XCTAssertEqual(type("use uitest"), "use uitest\nDatabase changed\nseekdb> ")
        type("create table t (id int, name varchar(20));")
        XCTAssertTrue(type("insert into t values (1, 'it''s'), (2, NULL);").contains("Records: 2  Duplicates: 0  Warnings: 0"))

        XCTAssertEqual(type("select *", until: "     -> "), "select *\n     -> ")
        let rows = type("from t\\G")
        XCTAssertTrue(rows.contains("*************************** 2. row ***************************\n  id: 2\nname: NULL\n"), rows)
        XCTAssertTrue(rows.contains("name: it's\n"), rows)
        XCTAssertTrue(rows.contains("2 rows in set"), rows)
        keep("vertical rows")

        terminal.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(text.hasSuffix("seekdb> from t\\G"), String(text.suffix(200)))
        terminal.typeKey("c", modifierFlags: .control)
        XCTAssertTrue(text.hasSuffix("seekdb> from t\\G^C\nseekdb> "), String(text.suffix(200)))

        XCTAssertEqual(type("select 'open", until: "     '> "), "select 'open\n     '> ")
        terminal.typeKey("c", modifierFlags: .control)
        XCTAssertTrue(text.hasSuffix("     '> ^C\nseekdb> "), String(text.suffix(200)))
        XCTAssertTrue(type("select count(*) from t;").contains("| count(*) |\n+----------+\n|        2 |\n"))

        XCTAssertEqual(type("quit", until: "$ "), "quit\nBye\n$ ")
        XCTAssertTrue(type("mysql").contains("Welcome to the SeekDB monitor."))
        terminal.typeKey("d", modifierFlags: .control)
        XCTAssertTrue(wait { $0.hasSuffix("seekdb> Bye\n$ ") }, String(text.suffix(200)))
        keep("after quit")
    }

    @discardableResult
    private func type(_ line: String, until prompt: String = "seekdb> ") -> String {
        let start = text.count
        terminal.typeText(line + "\n")
        var output = ""
        let done = wait { current in
            output = String(current.dropFirst(start))
            return output.hasSuffix(prompt)
        }
        XCTAssertTrue(done, "no \(prompt.debugDescription) after \(line.debugDescription): \(output.debugDescription)")
        return output
    }

    private func wait(timeout: TimeInterval = 30, until condition: (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition(text) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }

    private func keep(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
