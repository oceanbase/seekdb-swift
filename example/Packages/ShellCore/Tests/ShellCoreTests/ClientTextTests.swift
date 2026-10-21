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

struct ClientTextTests {
    @Test func alignsStatusFields() {
        let text = ClientText.status([("Connection id", "7"), ("Current database", "demo")])
        #expect(text == """
        --------------
        SeekDB shell for iOS, built on MySQLNIO

        Connection id:     7
        Current database:  demo
        --------------


        """)
    }

    @Test func endsTheBannerWithABlankLine() {
        #expect(ClientText.banner(connectionID: "7", serverVersion: "5.7.25").hasSuffix("statement.\n\n"))
    }
}
