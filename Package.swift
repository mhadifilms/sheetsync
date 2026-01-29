// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "GSheetSync",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "GSheetSync", targets: ["GSheetSync"])
    ],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.0")
    ],
    targets: [
        .executableTarget(
            name: "GSheetSync",
            dependencies: [
                "CoreXLSX"
            ],
            path: "GSheetSync"
        ),
        .testTarget(
            name: "GSheetSyncTests",
            dependencies: ["GSheetSync"],
            path: "GSheetSyncTests"
        )
    ]
)
