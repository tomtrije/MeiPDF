// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MeiPDF",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", .upToNextMajor(from: "2.6.0"))
    ],
    targets: [
        .executableTarget(
            name: "MeiPDF",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/MeiPDF"
        )
    ]
)
