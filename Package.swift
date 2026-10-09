// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "QuotaBar", targets: ["QuotaBar"])],
    targets: [
        .executableTarget(name: "QuotaBar", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "QuotaBarTests", dependencies: ["QuotaBar"])
    ]
)
