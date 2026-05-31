import XCTest

@testable import secure_vault

final class UtilitiesTests: XCTestCase {
    func testNormalizedCredentialFieldTrimsWhitespace() throws {
        XCTAssertEqual(try normalizedCredentialField("  github\n", name: "App"), "github")
    }

    func testNormalizedCredentialFieldRejectsEmptyValues() {
        XCTAssertThrowsError(try normalizedCredentialField(" \n\t", name: "App")) { error in
            XCTAssertTrue(String(describing: error).contains("App cannot be empty"))
        }
    }

    func testValidatePasswordInputOptionsRejectsMultipleSources() {
        XCTAssertThrowsError(try validatePasswordInputOptions("secret", passwordStdin: true)) { error in
            XCTAssertTrue(String(describing: error).contains("Use either --password or --password-stdin"))
        }
    }

    func testParseSecretJSONAcceptsScalarObjectValues() throws {
        let secret = try parseSecretJSON(
            """
            {"TOKEN":"abc123","RETRIES":3,"ENABLED":true,"EMPTY":null}
            """
        )

        XCTAssertEqual(secret["TOKEN"] as? String, "abc123")
        XCTAssertEqual(try secretValueString(secret["RETRIES"]!), "3")
        XCTAssertEqual(try secretValueString(secret["ENABLED"]!), "true")
        XCTAssertEqual(try secretValueString(secret["EMPTY"]!), "")
    }

    func testParseSecretJSONRejectsNestedValues() {
        XCTAssertThrowsError(try parseSecretJSON(#"{"TOKEN":{"nested":true}}"#)) { error in
            XCTAssertTrue(String(describing: error).contains("Secret values must be strings"))
        }
    }

    func testSecretJSONStringSortsKeys() throws {
        let json = try secretJSONString(["B": "two", "A": "one"])

        XCTAssertEqual(json, #"{"A":"one","B":"two"}"#)
    }

    func testShellExportLineQuotesSingleQuotes() throws {
        XCTAssertEqual(
            try shellExportLine(name: "API_TOKEN", value: "don't leak"),
            "export API_TOKEN='don'\\''t leak'"
        )
    }

    func testShellExportLineRejectsInvalidEnvironmentNames() {
        XCTAssertThrowsError(try shellExportLine(name: "1TOKEN", value: "secret")) { error in
            XCTAssertTrue(String(describing: error).contains("not a valid environment variable name"))
        }
    }
}
