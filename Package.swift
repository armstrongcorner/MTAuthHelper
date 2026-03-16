// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MTAuthHelper",
    
    platforms: [
        .iOS(.v15)
    ],
    
    products: [
        .library(
            name: "MTAuthHelper",
            targets: ["MTAuthHelper"]
        ),
    ],
    
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "12.10.0"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "9.1.0")
    ],
    
    targets: [
        .target(
            name: "MTAuthHelper",
            
            dependencies: [
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS")
            ],
            
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "MTAuthHelperTests",
            dependencies: ["MTAuthHelper"]
        ),
    ]
)
