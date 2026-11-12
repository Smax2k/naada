// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Naada",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Naada", targets: ["Naada"])
    ],
    targets: [
        .target(
            name: "CShine",
            path: "Sources/CShine",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("private")
            ]
        ),
        .target(
            name: "NaadaCore",
            dependencies: ["CShine"],
            path: "Sources/NaadaCore"
        ),
        .executableTarget(
            name: "Naada",
            dependencies: ["NaadaCore", "CShine"],
            path: "Sources/Naada",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "NaadaCoreTests",
            dependencies: ["NaadaCore", "CShine"],
            path: "Tests/NaadaCoreTests"
        )
    ]
)
