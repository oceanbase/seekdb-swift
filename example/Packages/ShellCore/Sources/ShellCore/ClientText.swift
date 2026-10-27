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

public enum ClientText {
    public static func banner(connectionID: String, serverVersion: String) -> String {
        [
            "Welcome to the SeekDB monitor.  Commands end with ; or \\g.",
            "Your SeekDB connection id is \(connectionID)",
            "Server version: \(serverVersion)",
            "",
            "Type 'help;' or '\\h' for help. Type '\\c' to clear the current input statement.",
            "",
            "",
        ].joined(separator: "\n")
    }

    public static let help = [
        "",
        "For information about SeekDB, visit https://github.com/oceanbase/seekdb",
        "",
        "List of all SeekDB shell commands:",
        "Note that all text commands must be first on line and end with ';'",
        "?         (\\?) Synonym for `help'.",
        "clear     (\\c) Clear the current input statement.",
        "delimiter (\\d) Set statement delimiter.",
        "ego       (\\G) Send command to the server, display result vertically.",
        "exit      (\\q) Exit the client. Same as quit.",
        "go        (\\g) Send command to the server.",
        "help      (\\h) Display this help.",
        "quit      (\\q) Quit the client.",
        "status    (\\s) Get status information from the server.",
        "use       (\\u) Use another database. Takes database name as argument.",
        "",
        "Keys: up and down recall earlier lines, ^C clears the input, ^L clears the screen,",
        "^D on an empty line quits, and pinching changes the text size.",
        "",
        "",
    ].joined(separator: "\n")

    public static func status(_ fields: [(label: String, value: String)]) -> String {
        let width = (fields.map { $0.label.count }.max() ?? 0) + 3
        var lines = ["--------------", "SeekDB shell for iOS, built on MySQLNIO", ""]
        lines += fields.map { ($0.label + ":").padding(toLength: width, withPad: " ", startingAt: 0) + $0.value }
        lines += ["--------------", "", ""]
        return lines.joined(separator: "\n")
    }
}
