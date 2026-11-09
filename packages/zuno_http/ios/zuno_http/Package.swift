// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "zuno_http",
    platforms: [
        .iOS("13.0"),
    ],
    products: [
        .library(name: "zuno-http", targets: ["zuno_http"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "zuno_http",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ]
        ),
    ]
)
