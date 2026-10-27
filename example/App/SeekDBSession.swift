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
import NIOPosix
import SeekDB
import ShellCore

actor SeekDBSession {
    struct Info: Sendable {
        var directory: String
        var socket: String
        var user: String
    }

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var database: SeekDB?
    private var connection: MySQLConnection?
    private var socket = ""
    private var user = "root"

    func start(directory: URL, resetting reset: Bool) async throws -> Info {
        if reset {
            try? FileManager.default.removeItem(at: directory)
        }
        let database = try await Self.open(directory.path)
        self.database = database
        let options = try database.connectionOptions()
        guard let socket = options.unix_socket else {
            throw QueryError(message: "seekdb reported no Unix socket (transport \(options.transport))")
        }
        self.socket = socket
        user = options.user ?? "root"
        return Info(directory: directory.path, socket: socket, user: user)
    }

    func disconnect() async {
        guard let connection else { return }
        self.connection = nil
        try? await connection.close().get()
    }

    func execute(_ sql: String) async throws -> [QueryResult] {
        let connection = try await openConnection()
        let command = QueryCommand(sql: sql)
        do {
            try await connection.send(command, logger: connection.logger).get()
        } catch {
            if connection.isClosed {
                self.connection = nil
            }
            throw Self.queryError(error)
        }
        return command.results
    }

    static func queryError(_ error: Error) -> QueryError {
        switch error {
        case let error as QueryError:
            return error
        case MySQLError.server(let packet):
            return QueryError(code: packet.errorCode.rawValue, sqlState: packet.sqlState, message: packet.errorMessage)
        case let error as MySQLError:
            return QueryError(message: error.message)
        default:
            return QueryError(message: error.localizedDescription)
        }
    }

    private func openConnection() async throws -> MySQLConnection {
        if let connection, !connection.isClosed {
            return connection
        }
        do {
            let connection = try await MySQLConnection.connect(
                to: try SocketAddress(unixDomainSocketPath: socket),
                username: user,
                database: "",
                password: nil,
                tlsConfiguration: nil,
                on: group.next()
            ).get()
            self.connection = connection
            return connection
        } catch {
            throw Self.queryError(error)
        }
    }

    private static func open(_ path: String) async throws -> SeekDB {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try SeekDB.open(path) })
            }
        }
    }
}
