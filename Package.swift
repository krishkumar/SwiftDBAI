// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SwiftDBAI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "SwiftDBAI",
            targets: ["SwiftDBAI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/huggingface/AnyLanguageModel.git", from: "0.8.0"),
        .package(url: "https://github.com/nalexn/ViewInspector.git", from: "0.10.0"),
    ],
    targets: [
        .target(
            name: "SwiftDBAI",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SwiftDBAITests",
            dependencies: ["SwiftDBAI", "ViewInspector"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
