// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WageFlow",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "SalaryPanel", targets: ["SalaryPanel"])],
    targets: [
        .target(name: "SalaryCore"),
        .executableTarget(name: "SalaryPanel", dependencies: ["SalaryCore"]),
        .executableTarget(name: "SalaryCoreChecks", dependencies: ["SalaryCore"], path: "Tests/SalaryCoreTests")
    ]
)
