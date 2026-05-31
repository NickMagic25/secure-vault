import Foundation

func printErr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
