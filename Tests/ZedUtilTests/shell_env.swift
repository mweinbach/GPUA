// Swift-only: Unit tests for shell_env environment serialization and login shell capture

import Foundation
import Testing
@testable import ZedUtil

@Suite("ShellEnv Tests")
struct ShellEnvTests {
    @Test
    func test_env_json_serialization_and_deserialization() throws {
        let sampleEnv = [
            "ZED_TEST": "1",
            "PATH": "/usr/bin:/bin",
            "HOME": "/Users/zed",
            "EMPTY": "",
        ]

        let json = try formatEnvJson(sampleEnv)
        #expect(json.contains("\"ZED_TEST\" : \"1\"") || json.contains("\"ZED_TEST\": \"1\""))
        #expect(json.contains("\"HOME\" : \"/Users/zed\"") || json.contains("\"HOME\": \"/Users/zed\""))

        let parsed = try parseEnvJson(json)
        #expect(parsed == sampleEnv)
    }

    @Test
    func test_env_json_error_handling() {
        #expect(throws: (any Error).self) {
            _ = try parseEnvJson("invalid-json{not_a_dict}")
        }
    }

    @Test
    func test_current_environment_serialization() throws {
        let currentEnv = ProcessInfo.processInfo.environment
        let json = try formatEnvJson(currentEnv)
        let parsed = try parseEnvJson(json)
        #expect(parsed.count == currentEnv.count)
        for (k, v) in currentEnv {
            #expect(parsed[k] == v)
        }
    }

    @Test
    func test_shell_env_error_description() {
        let error = ShellEnvError("test error message")
        #expect(error.description == "test error message")
    }
}
