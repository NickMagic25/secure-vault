import Foundation
import XCTest

final class MakefileSecurityTests: XCTestCase {
    func testSignRejectsShellMetacharactersInSigningVariables() throws {
        for assignment in [
            "BUNDLE_ID=io.securevault; touch /tmp/secure-vault-bundle-pwned #",
            "DEVELOPMENT_TEAM=TEAMID1234; touch /tmp/secure-vault-team-pwned #",
        ] {
            let result = try runMake([
                "-n",
                "sign",
                "DEVELOPMENT_TEAM=TEAMID1234",
                "BUNDLE_ID=io.securevault",
                assignment,
            ])

            XCTAssertNotEqual(result.status, 0, "Expected make to reject \(assignment)")
            XCTAssertTrue(result.output.contains("unsafe shell metacharacter"), result.output)
        }
    }

    func testInstallRejectsShellMetacharactersInInstallPaths() throws {
        for assignment in [
            "APP_INSTALL_DIR=\"; touch /tmp/secure-vault-wrapper-pwned #",
            "BIN_DIR=\"; touch /tmp/secure-vault-bin-pwned #",
        ] {
            let result = try runMake([
                "-n",
                "install",
                "DEVELOPMENT_TEAM=TEAMID1234",
                assignment,
            ])

            XCTAssertNotEqual(result.status, 0, "Expected make to reject \(assignment)")
            XCTAssertTrue(result.output.contains("unsafe shell metacharacter"), result.output)
        }
    }

    func testInstallDryRunAllowsNormalValues() throws {
        let result = try runMake([
            "-n",
            "install",
            "DEVELOPMENT_TEAM=TEAMID1234",
            "BUNDLE_ID=com.example.vault",
        ])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains(#""DEVELOPMENT_TEAM=TEAMID1234""#), result.output)
        XCTAssertTrue(result.output.contains(#""PRODUCT_BUNDLE_IDENTIFIER=com.example.vault""#), result.output)
        XCTAssertTrue(result.output.contains("exec \"/Applications/SecureVault.app/Contents/MacOS/secure-vault\" \"$@\""), result.output)
    }

    private func runMake(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/make")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryRoot

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
