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
import ShellCore

@MainActor
final class MySQLClient {
    private enum Mode {
        case starting
        case client
        case shell
        case failed
    }

    private let terminal: TerminalTextView
    private let session = SeekDBSession()
    private let defaults = UserDefaults.standard
    private var buffer = InputBuffer()
    private var history: CommandHistory
    private var mode = Mode.starting
    private var socket = ""

    init(terminal: TerminalTextView) {
        self.terminal = terminal
        history = CommandHistory(entries: defaults.stringArray(forKey: "history") ?? [])
        terminal.onSubmit = { [weak self] lines, remainder in
            self?.submit(lines, remainder: remainder)
        }
        terminal.onInterrupt = { [weak self] in
            self?.interrupt()
        }
        terminal.onEndOfInput = { [weak self] in
            self?.endOfInput()
        }
        terminal.onRecall = { [weak self] older in
            self?.recall(older: older)
        }
    }

    func start() {
        terminal.write("Starting seekdb inside this app...\n")
        Task {
            do {
                let directory = try FileManager.default
                    .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("seekdb", isDirectory: true)
                let info = try await session.start(directory: directory, resetting: defaults.bool(forKey: "resetData"))
                socket = info.socket
                terminal.write("$ mysql -u root\n")
                await connect()
                terminal.prompt(prompt)
                if let script = defaults.string(forKey: "runSQL") {
                    terminal.enter(script + "\n")
                }
            } catch {
                mode = .failed
                terminal.write("ERROR: seekdb did not start: \(SeekDBSession.queryError(error).message)\n")
            }
        }
    }

    private var prompt: String {
        mode == .shell ? "$ " : buffer.prompt
    }

    private func connect() async {
        mode = .client
        buffer.clear()
        var row = await firstRow("SELECT CONNECTION_ID(), VERSION(), @@version_comment")
        if row == nil {
            row = await firstRow("SELECT CONNECTION_ID(), VERSION()")
        }
        let connectionID = row?.first.flatMap { $0 } ?? "?"
        let version = row.map { $0.dropFirst().compactMap { $0 }.joined(separator: " ") } ?? "unknown"
        terminal.write(ClientText.banner(connectionID: connectionID, serverVersion: version))
    }

    private func submit(_ lines: [String], remainder: String) {
        Task {
            for (index, line) in lines.enumerated() {
                if index > 0 {
                    terminal.write(prompt + line + "\n")
                }
                await process(line)
            }
            terminal.prompt(prompt, input: remainder)
        }
    }

    private func process(_ line: String) async {
        history.record(line)
        defaults.set(history.entries, forKey: "history")
        switch mode {
        case .client:
            for event in buffer.feed(line) {
                await handle(event)
                if mode != .client {
                    break
                }
            }
        case .shell:
            await runShellCommand(line)
        case .starting, .failed:
            break
        }
    }

    private func handle(_ event: InputEvent) async {
        switch event {
        case let .statement(sql, vertical):
            await execute(sql, vertical: vertical)
        case .noQuery:
            terminal.write("ERROR: \nNo query specified\n\n")
        case .command(.help):
            terminal.write(ClientText.help)
        case .command(.quit):
            await quit()
        case .command(.status):
            await showStatus()
        case .command(.use(let name)):
            if name.isEmpty {
                terminal.write("ERROR: USE must be followed by a database name\n")
            } else {
                await execute("USE `\(name.replacingOccurrences(of: "`", with: "``"))`", vertical: false)
            }
        case .command(.unknown(let name)):
            terminal.write("ERROR: Unknown command '\(name)'.\n")
        case .command(.unsupported(let name)):
            terminal.write("ERROR: '\(name)' is not available in this shell.\n")
        case .command(.error(let message)):
            terminal.write(message + "\n")
        }
    }

    private func execute(_ sql: String, vertical: Bool) async {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let results = try await session.execute(sql)
            terminal.write(OutputFormatter.render(results, statement: sql, elapsed: clock.now - start, vertical: vertical))
        } catch {
            terminal.write(OutputFormatter.render(error: SeekDBSession.queryError(error)))
        }
    }

    private func firstRow(_ sql: String) async -> [String?]? {
        guard case let .rows(_, rows)? = try? await session.execute(sql).first else { return nil }
        return rows.first
    }

    private func showStatus() async {
        let row = await firstRow("SELECT CONNECTION_ID(), DATABASE(), CURRENT_USER(), VERSION()") ?? []
        func value(_ index: Int) -> String {
            index < row.count ? row[index] ?? "" : ""
        }
        terminal.write(ClientText.status([
            ("Connection id", value(0)),
            ("Current database", value(1)),
            ("Current user", value(2)),
            ("Using delimiter", buffer.delimiter),
            ("Server version", value(3)),
            ("Protocol version", "10"),
            ("Connection", "Localhost via UNIX socket"),
            ("UNIX socket", socket),
        ]))
    }

    private func quit() async {
        terminal.write("Bye\n")
        await session.disconnect()
        buffer.clear()
        mode = .shell
    }

    private func runShellCommand(_ line: String) async {
        guard let command = line.split(whereSeparator: \.isWhitespace).first.map(String.init) else { return }
        if command == "mysql" {
            await connect()
        } else {
            terminal.write("sh: \(command): command not found\n")
        }
    }

    private func interrupt() {
        guard mode == .client || mode == .shell else { return }
        terminal.cancelInput()
        buffer.clear()
        terminal.prompt(prompt)
    }

    private func endOfInput() {
        guard mode == .client, buffer.isEmpty else { return }
        terminal.finishInput()
        Task {
            await quit()
            terminal.prompt(prompt)
        }
    }

    private func recall(older: Bool) -> String? {
        older ? history.older(than: terminal.currentInput) : history.newer()
    }
}
