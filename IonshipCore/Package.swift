// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IonshipCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "IonshipCore", targets: ["IonshipCore"]),
        .executable(name: "ionship-probe", targets: ["IonshipProbe"]),
    ],
    targets: [
        .target(name: "ObjCExceptionCatcher"),
        .target(name: "IonshipCore", dependencies: ["ObjCExceptionCatcher"], resources: [.copy("Resources/vocab.txt")]),
        .executableTarget(name: "IonshipProbe", dependencies: ["IonshipCore"]),
        .testTarget(name: "IonshipCoreTests", dependencies: ["IonshipCore"], resources: [.copy("Resources/tokenizer-golden.json")]),
    ]
)
