
// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FestMest",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FestMest",
            targets: ["FestMest"]
        ),
    ],
    dependencies:[
        .package(path: "localPackages/Arti"),
        .package(path: "localPackages/BitLogger"),
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", exact: "0.21.1")
    ],
    targets: [
        .executableTarget(
            name: "FestMest",
            dependencies: [
                .product(name: "P256K", package: "swift-secp256k1"),
                .product(name: "BitLogger", package: "BitLogger"),
                .product(name: "Tor", package: "Arti")
            ],
            path: "bitchat",
            exclude: [
                "Info.plist",
                "Assets.xcassets",
                "bitchat.entitlements",
                "bitchat-macOS.entitlements",
                "LaunchScreen.storyboard",
                "ViewModels/Extensions/README.md",
                "BitchatApp.swift"  // Excluded - using FestMestApp.swift instead
            ],
            resources: [
                .process("Localizable.xcstrings"),
                .process("Features/festival/TripSchedule.json")
            ]
        ),
        .testTarget(
            name: "FestMestTests",
            dependencies: ["FestMest"],
            path: "bitchatTests",
            exclude: [
                "Info.plist",
                "README.md"
            ],
            resources: [
                .process("Localization"),
                .process("Noise")
            ]
        )
    ]
)
