// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MacDuo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacDuo", targets: ["MacDuo"])],
    targets: [
        .target(name: "FocusCore"),
        .executableTarget(name: "MacDuo", dependencies: ["FocusCore"], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("IOKit"), .linkedFramework("Carbon")]),
        .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"]),
        .testTarget(name: "PlaneRendererTests", dependencies: ["MacDuo", "FocusCore"])
    ],
    swiftLanguageModes: [.v5]
)
