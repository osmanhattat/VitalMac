// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VitalMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VitalMac", targets: ["VitalMac"])
    ],
    targets: [
        // Sıcaklık (IOHID) ve fan (SMC) için C ara katmanı.
        .target(name: "CSensors"),
        .executableTarget(
            name: "VitalMac",
            dependencies: ["CSensors"],
            path: "Sources/VitalMac",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        )
    ]
)
