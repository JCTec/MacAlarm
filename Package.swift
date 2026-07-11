// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacAlarm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MacAlarmCore",
            targets: ["MacAlarmCore"]
        ),
        .library(
            name: "MacAlarmAppSupport",
            targets: ["MacAlarmAppSupport"]
        ),
        .executable(
            name: "macalarm-probe",
            targets: ["MacAlarmProbe"]
        ),
        .executable(
            name: "macalarm-agent",
            targets: ["MacAlarmAgent"]
        ),
        .executable(
            name: "macalarmctl",
            targets: ["MacAlarmCLI"]
        ),
        .executable(
            name: "MacAlarmApp",
            targets: ["MacAlarmApp"]
        ),
        .executable(
            name: "macalarm-tests",
            targets: ["MacAlarmTests"]
        ),
    ],
    targets: [
        .target(
            name: "MacAlarmCore"
        ),
        .executableTarget(
            name: "MacAlarmProbe",
            dependencies: ["MacAlarmCore"]
        ),
        .executableTarget(
            name: "MacAlarmAgent",
            dependencies: ["MacAlarmCore"]
        ),
        .target(
            name: "MacAlarmCLIKit",
            dependencies: ["MacAlarmCore"]
        ),
        .executableTarget(
            name: "MacAlarmCLI",
            dependencies: ["MacAlarmCore", "MacAlarmCLIKit"]
        ),
        .executableTarget(
            name: "MacAlarmApp",
            dependencies: ["MacAlarmAppSupport"]
        ),
        .executableTarget(
            name: "MacAlarmTests",
            dependencies: ["MacAlarmCore", "MacAlarmAppSupport", "MacAlarmCLIKit"]
        ),
        .target(
            name: "MacAlarmAppSupport",
            dependencies: ["MacAlarmCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
