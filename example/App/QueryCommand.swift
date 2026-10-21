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
import MySQLNIO
import NIOCore
import ShellCore

final class QueryCommand: MySQLCommand {
    private enum Stage {
        case ready
        case columns
        case columnsEnd
        case rows
    }

    private let sql: String
    private var stage = Stage.ready
    private var columnCount = 0
    private var columns: [MySQLProtocol.ColumnDefinition41] = []
    private var rows: [[String?]] = []
    private(set) var results: [QueryResult] = []

    init(sql: String) {
        self.sql = sql
    }

    func activate(capabilities: MySQLProtocol.CapabilityFlags) throws -> MySQLCommandState {
        MySQLCommandState(response: [try .encode(MySQLProtocol.COM_QUERY(query: sql), capabilities: capabilities)])
    }

    func handle(packet: inout MySQLPacket, capabilities: MySQLProtocol.CapabilityFlags) throws -> MySQLCommandState {
        if packet.isError {
            throw MySQLError.server(try packet.decode(MySQLProtocol.ERR_Packet.self, capabilities: capabilities))
        }
        switch stage {
        case .ready:
            if packet.isOK {
                let ok = try decodeOK(&packet, capabilities: capabilities)
                let info = ok.info.trimmingCharacters(in: .whitespaces)
                results.append(.ok(affectedRows: ok.affectedRows, warnings: ok.warningsCount ?? 0, info: info))
                return next(after: ok.statusFlags)
            }
            columnCount = Int(try packet.decode(MySQLProtocol.COM_QUERY_Response.self, capabilities: capabilities).columnCount)
            columns = []
            rows = []
            stage = .columns
        case .columns:
            columns.append(try packet.decode(MySQLProtocol.ColumnDefinition41.self, capabilities: capabilities))
            if columns.count == columnCount {
                stage = capabilities.contains(.CLIENT_DEPRECATE_EOF) ? .rows : .columnsEnd
            }
        case .columnsEnd:
            stage = .rows
        case .rows:
            if let status = endOfRows(packet, capabilities: capabilities) {
                let resultColumns = columns.map { Column(name: $0.name, isNumeric: $0.columnType.isNumeric) }
                results.append(.rows(columns: resultColumns, rows: rows))
                return next(after: status)
            }
            let row = try MySQLProtocol.TextResultSetRow.decode(from: &packet, columnCount: columns.count)
            rows.append(row.values.map { $0.map { String(buffer: $0) } })
        }
        return MySQLCommandState()
    }

    private func decodeOK(_ packet: inout MySQLPacket, capabilities: MySQLProtocol.CapabilityFlags) throws -> MySQLProtocol.OK_Packet {
        var negotiated = capabilities
        negotiated.remove(.CLIENT_SESSION_TRACK)
        return try packet.decode(MySQLProtocol.OK_Packet.self, capabilities: negotiated)
    }

    private func next(after status: MySQLProtocol.StatusFlags) -> MySQLCommandState {
        guard status.contains(.SERVER_MORE_RESULTS_EXISTS) else {
            return MySQLCommandState(done: true)
        }
        stage = .ready
        return MySQLCommandState()
    }

    private func endOfRows(_ packet: MySQLPacket, capabilities: MySQLProtocol.CapabilityFlags) -> MySQLProtocol.StatusFlags? {
        guard packet.isEOF else { return nil }
        var copy = packet
        if capabilities.contains(.CLIENT_DEPRECATE_EOF) {
            return (try? decodeOK(&copy, capabilities: capabilities))?.statusFlags
        }
        guard copy.payload.readableBytes < 9 else { return nil }
        guard copy.payload.readableBytes >= 5 else { return [] }
        copy.payload.moveReaderIndex(forwardBy: 3)
        let status = copy.payload.readInteger(endianness: .little, as: UInt16.self) ?? 0
        return MySQLProtocol.StatusFlags(rawValue: .init(status))
    }
}

private extension MySQLProtocol.DataType {
    var isNumeric: Bool {
        [.tiny, .short, .long, .longlong, .int24, .float, .double, .decimal, .newdecimal, .year].contains(self)
    }
}
