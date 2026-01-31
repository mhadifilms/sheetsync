// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "sheetsync",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "sheetsync", targets: ["sheetsync"])
    ],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.0")
    ],
    targets: [
        .executableTarget(
            name: "sheetsync",
            dependencies: [
                "CoreXLSX"
            ],
            path: "SheetSync"
        ),
        .testTarget(
            name: "sheetsync-tests",
            dependencies: ["sheetsync"],
            path: "SheetSyncTests"
        )
    ]
)
