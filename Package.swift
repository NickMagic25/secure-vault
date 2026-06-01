// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "secure-vault",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SecureVaultCore", targets: ["SecureVaultCore"]),
        .library(name: "SecureVaultUI", targets: ["SecureVaultUI"]),
        .executable(name: "secure-vault", targets: ["SecureVaultCLI"]),
        .executable(name: "SecureVault", targets: ["SecureVaultApp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
    ],
    targets: [
        .target(
            name: "SecureVaultCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "SecureVaultCLI",
            dependencies: [
                "SecureVaultCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "SecureVaultUI",
            dependencies: ["SecureVaultCore"]
        ),
        .executableTarget(
            name: "SecureVaultApp",
            dependencies: ["SecureVaultUI"]
        ),
        .testTarget(
            name: "SecureVaultUITests",
            dependencies: ["SecureVaultUI"]
        ),
    ]
)
