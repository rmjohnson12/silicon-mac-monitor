// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Silicon",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Silicon", targets: ["Silicon"])],
    targets: [
        .target(name: "SensorBridge", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "Silicon", dependencies: ["SensorBridge"], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("IOKit")])
    ]
)
