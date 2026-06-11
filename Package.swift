// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DailyJournal",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DailyJournal",
            targets: ["DailyJournal"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.20.0"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "DailyJournal",
            dependencies: [
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS")
            ]
        )
    ]
)
