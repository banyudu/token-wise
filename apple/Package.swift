// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TokenWise",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TokenWiseCore", targets: ["TokenWiseCore"]),
        .executable(name: "token-wise", targets: ["token-wise"]),
        .executable(name: "TokenWiseApp", targets: ["TokenWiseApp"]),
    ],
    targets: [
        // Pure-Swift core: parsing, pricing, aggregation, AI analysis.
        // No external dependencies — uses only Foundation and the system
        // SQLite3 module, so it builds fully offline.
        .target(
            name: "TokenWiseCore"
        ),
        // Command-line front end (token-wise total/today/sessions/analyze).
        .executableTarget(
            name: "token-wise",
            dependencies: ["TokenWiseCore"]
        ),
        // SwiftUI menu-bar + window app.
        .executableTarget(
            name: "TokenWiseApp",
            dependencies: ["TokenWiseCore"]
        ),
        .testTarget(
            name: "TokenWiseCoreTests",
            dependencies: ["TokenWiseCore"]
        ),
    ]
)
