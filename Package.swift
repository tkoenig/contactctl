// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let infoPlist = packageRoot.appendingPathComponent("Resources/Info.plist").path

let package = Package(
    name: "contactctl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "contactctl", targets: ["contactctl"]),
        .executable(name: "contactctl-core-checks", targets: ["ContactCoreChecks"])
    ],
    targets: [
        .target(name: "ContactCore"),
        .executableTarget(
            name: "contactctl",
            dependencies: ["ContactCore"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist
                ])
            ]
        ),
        .executableTarget(
            name: "ContactCoreChecks",
            dependencies: ["ContactCore"],
            path: "Checks/ContactCoreChecks"
        )
    ]
)
