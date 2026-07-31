// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "sokki",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "sokki", targets: ["sokki"]),
        .library(name: "SokkiKit", targets: ["SokkiKit"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            from: "1.17.0"
        ),
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            // pre-1.0 は minor でも破壊的変更がありうるため upToNextMinor で上限を絞る
            .upToNextMinor(from: "0.15.5")
        ),
    ],
    targets: [
        // ライブラリターゲット：ビジネスロジック + UI（RenderPreview / ExecuteSnippet 対応）
        .target(
            name: "SokkiKit",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/SokkiKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        // 実行可能ターゲット：@main のみ
        .executableTarget(
            name: "sokki",
            dependencies: ["SokkiKit"],
            path: "Sources/sokki",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "sokkiTests",
            dependencies: [
                "SokkiKit",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/sokkiTests"
        )
    ]
)
