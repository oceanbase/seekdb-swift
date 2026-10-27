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

struct InputBufferTests {
    @Test func runsAStatementEndingWithTheDelimiter() {
        var buffer = InputBuffer()
        #expect(buffer.prompt == "seekdb> ")
        #expect(buffer.feed("select 1;") == [.statement("select 1", vertical: false)])
        #expect(buffer.prompt == "seekdb> ")
    }

    @Test func continuesAStatementOverSeveralLines() {
        var buffer = InputBuffer()
        #expect(buffer.feed("select") == [])
        #expect(buffer.prompt == "     -> ")
        #expect(buffer.feed("  1 + 1;") == [.statement("select\n  1 + 1", vertical: false)])
        #expect(buffer.prompt == "seekdb> ")
    }

    @Test func showsWhichQuoteOrCommentIsOpen() {
        var buffer = InputBuffer()
        _ = buffer.feed("select 'a")
        #expect(buffer.prompt == "     '> ")
        #expect(buffer.feed("b';") == [.statement("select 'a\nb'", vertical: false)])
        _ = buffer.feed("select \"a")
        #expect(buffer.prompt == "     \"> ")
        buffer.clear()
        _ = buffer.feed("select `a")
        #expect(buffer.prompt == "     `> ")
        buffer.clear()
        _ = buffer.feed("select /* a")
        #expect(buffer.prompt == "    /*> ")
        #expect(buffer.feed("b */ 1;") == [.statement("select /* a\nb */ 1", vertical: false)])
    }

    @Test func ignoresDelimitersInQuotesAndEscapes() {
        var buffer = InputBuffer()
        #expect(buffer.feed(#"select 'it\'s; fine', "a;b", `c;d`;"#) == [.statement(#"select 'it\'s; fine', "a;b", `c;d`"#, vertical: false)])
    }

    @Test func runsSeveralStatementsFromOneLine() {
        var buffer = InputBuffer()
        #expect(buffer.feed("select 1; select 2\\G select 3\\g") == [
            .statement("select 1", vertical: false),
            .statement("select 2", vertical: true),
            .statement("select 3", vertical: false),
        ])
    }

    @Test func clearsTheCurrentStatement() {
        var buffer = InputBuffer()
        _ = buffer.feed("select")
        #expect(buffer.feed("1 \\c") == [])
        #expect(buffer.isEmpty)
        #expect(buffer.prompt == "seekdb> ")
    }

    @Test func dropsLineCommentsAndCommentOnlyLines() {
        var buffer = InputBuffer()
        #expect(buffer.feed("-- just a note") == [])
        #expect(buffer.feed("# another") == [])
        #expect(buffer.prompt == "seekdb> ")
        #expect(buffer.feed("select 1 -- trailing; note") == [])
        #expect(buffer.feed(";") == [.statement("select 1", vertical: false)])
        #expect(buffer.feed("select 1--1;") == [.statement("select 1--1", vertical: false)])
    }

    @Test func reportsAnEmptyQuery() {
        var buffer = InputBuffer()
        #expect(buffer.feed(";") == [.noQuery])
        #expect(buffer.feed("select 1;;") == [.statement("select 1", vertical: false), .noQuery])
        #expect(buffer.feed("go") == [.noQuery])
    }

    @Test func changesTheDelimiter() {
        var buffer = InputBuffer()
        #expect(buffer.feed("DELIMITER //") == [])
        #expect(buffer.delimiter == "//")
        #expect(buffer.feed("create procedure p() begin select 1; select 2; end //") == [
            .statement("create procedure p() begin select 1; select 2; end", vertical: false),
        ])
        #expect(buffer.feed("\\d ;") == [])
        #expect(buffer.delimiter == ";")
        #expect(buffer.feed("delimiter") == [.command(.error("DELIMITER must be followed by a 'delimiter' character or string"))])
    }

    @Test func recognizesClientCommands() {
        var buffer = InputBuffer()
        #expect(buffer.feed("help") == [.command(.help)])
        #expect(buffer.feed("\\h") == [.command(.help)])
        #expect(buffer.feed("exit;") == [.command(.quit)])
        #expect(buffer.feed("\\q") == [.command(.quit)])
        #expect(buffer.feed("status") == [.command(.status)])
        #expect(buffer.feed("\\s") == [.command(.status)])
        #expect(buffer.feed("use demo;") == [.command(.use("demo"))])
        #expect(buffer.feed("USE `my db`") == [.command(.use("my db"))])
        #expect(buffer.feed("\\u demo") == [.command(.use("demo"))])
        #expect(buffer.feed("source a.sql") == [.command(.unsupported("source"))])
        #expect(buffer.feed("select 1 \\x") == [.command(.unknown("\\x"))])
    }

    @Test func treatsCommandWordsInsideAStatementAsSQL() {
        var buffer = InputBuffer()
        _ = buffer.feed("select")
        #expect(buffer.feed("help;") == [.statement("select\nhelp", vertical: false)])
    }
}
