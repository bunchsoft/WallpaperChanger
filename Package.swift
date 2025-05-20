// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WallpaperChanger",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "WallpaperChanger",
            targets: ["WallpaperChanger"]),
    ],
    dependencies: [
        // No external dependencies for now
    ],
    targets: [
        .executableTarget(
            name: "WallpaperChanger",
            dependencies: []),
    ]
)
