// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Intact",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Intact",
            path: "Sources/Intact",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("PDFKit")
            ]
        )
    ]
)
