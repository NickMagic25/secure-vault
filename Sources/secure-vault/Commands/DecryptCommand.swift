import ArgumentParser
import Foundation

struct DecryptCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "decrypt",
        abstract: "Decrypt a file or stdin. Requires Touch ID or Apple Watch."
    )

    @Option(name: .shortAndLong, help: "Key tag to use for decryption.")
    var tag: String = "io.securevault.default"

    @Option(name: .shortAndLong, help: "Encrypted binary file to decrypt. Reads base64 from stdin if omitted.")
    var input: String?

    @Option(name: .shortAndLong, help: "Output file for decrypted data. Writes to stdout if omitted.")
    var output: String?

    @Option(name: .long, help: "Reason string shown in the Touch ID / Apple Watch prompt.")
    var reason: String = "Decrypt data with Secure Vault"

    func run() throws {
        let ciphertext: Data
        if let path = input {
            ciphertext = try Data(contentsOf: URL(fileURLWithPath: path))
        } else {
            let raw = FileHandle.standardInput.readDataToEndOfFile()
            let b64 = String(data: raw, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let decoded = Data(base64Encoded: b64) else {
                throw ValidationError("Could not base64-decode input. Pipe 'encrypt' output directly or use --input with a binary file.")
            }
            ciphertext = decoded
        }

        printErr("Authenticating... (Touch ID or Apple Watch required)")
        let plaintext = try SecureEnclaveManager.decrypt(data: ciphertext, tag: tag, reason: reason)

        if let path = output {
            try plaintext.write(to: URL(fileURLWithPath: path))
            printErr("Decrypted to \(path)")
        } else if let text = String(data: plaintext, encoding: .utf8) {
            print(text, terminator: "")
        } else {
            FileHandle.standardOutput.write(plaintext)
        }
    }
}
