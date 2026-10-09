// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OdeCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "OdeCore", targets: ["OdeCore"]),
        .executable(name: "ode-probe", targets: ["OdeProbe"]),
    ],
    targets: [
        .target(name: "ObjCExceptionCatcher"),
        .target(name: "OdeCore", dependencies: ["ObjCExceptionCatcher"], resources: [.copy("Resources/vocab.txt")]),
        .executableTarget(name: "OdeProbe", dependencies: ["OdeCore"]),
        .testTarget(name: "OdeCoreTests", dependencies: ["OdeCore"], resources: [.copy("Resources/tokenizer-golden.json")]),
    ]
)
