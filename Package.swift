// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WageFlow",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WageFlow", targets: ["WageFlow"])],
    targets: [
        .target(name: "SalaryCore"),
        .executableTarget(name: "WageFlow", dependencies: ["SalaryCore"]),
        .executableTarget(name: "SalaryCoreChecks", dependencies: ["SalaryCore"], path: "Tests/SalaryCoreTests")
    ]
)
