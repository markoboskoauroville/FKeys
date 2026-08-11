// swift-tools-version: 5.9
import PackageDescription

// 5.9 deliberately. The manifest is compiled by whatever Swift the user has,
// and the 6.0 manifest API (swiftLanguageModes) does not exist on a Command
// Line Tools install that lags Xcode by a release. Below 6.0 the default
// language mode is already Swift 5, which is what this code expects.
let package = Package(
    name: "FKeys",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FKeys", targets: ["FKeys"])
    ],
    targets: [
        .executableTarget(
            name: "FKeys",
            path: "Sources/FKeys",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
