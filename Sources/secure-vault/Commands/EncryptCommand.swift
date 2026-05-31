import ArgumentParser
import Foundation

struct EncryptCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "encrypt",
        abstract: "Encrypt a file or stdin using the Secure Enclave public key. No authentication required."
    )

    @Option(name: .shortAndLong, help: "Key tag to use for encryption.")
    var tag: String = "io.securevault.default"

    @Option(name: .shortAndLong, help: "Input file to encrypt. Reads from stdin if omitted.")
    var input: String?

    @Option(name: .shortAndLong, help: "Output file (raw binary). Prints base64 to stdout if omitted.")
    var output: String?

    func run() throws {
        let plaintext: Data
        if let path = input {
            plaintext = try Data(contentsOf: URL(fileURLWithPath: path))
        } else {
            plaintext = FileHandle.standardInput.readDataToEndOfFile()
        }
        guard !plaintext.isEmpty else { throw ValidationError("Input is empty.") }

        let ciphertext = try SecureEnclaveManager.encrypt(data: plaintext, tag: tag)

        if let path = output {
            try ciphertext.write(to: URL(fileURLWithPath: path))
            printErr("Encrypted \(plaintext.count) bytes -> \(path) (\(ciphertext.count) bytes)")
        } else {
            print(ciphertext.base64EncodedString())
        }
    }
}
