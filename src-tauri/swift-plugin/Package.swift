// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StoreKitBridge",
    platforms: [.macOS(.v13)],
    products: [
        .library(
            name: "StoreKitBridge",
            type: .static,
            targets: ["StoreKitBridge"]
        )
    ],
    targets: [
        .target(
            name: "StoreKitBridge",
            path: "Sources/StoreKitBridge",
            linkerSettings: [
                .linkedFramework("StoreKit"),
                .linkedFramework("Foundation"),
            ]
        )
    ]
)
