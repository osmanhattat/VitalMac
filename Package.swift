// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacNabiz",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacNabiz", targets: ["MacNabiz"])
    ],
    targets: [
        // Sıcaklık (IOHID) ve fan (SMC) için C ara katmanı.
        .target(name: "CSensors"),
        .executableTarget(
            name: "MacNabiz",
            dependencies: ["CSensors"],
            path: "Sources/MacNabiz",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        )
    ]
)
