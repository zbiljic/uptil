import ProjectDescription

let sharedSettings: Settings = .settings(
    base: [
        "CLANG_ENABLE_MODULES": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "SWIFT_VERSION": "6.3",
    ],
    configurations: [
        .debug(name: .debug),
        // Keep test coverage instrumentation out of shipped builds.
        .release(name: .release, settings: ["ENABLE_CODE_COVERAGE": "NO"]),
    ]
)

let appSettings: Settings = .settings(
    base: [
        "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    ]
)

let cliSettings: Settings = .settings(
    base: [
        "PRODUCT_MODULE_NAME": "UpTilCLI",
        "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    ]
)

let project = Project(
    name: "UpTil",
    organizationName: "zbiljic",
    options: .options(
        automaticSchemesOptions: .disabled,
        developmentRegion: "en",
        textSettings: .textSettings(
            usesTabs: false,
            indentWidth: 4,
            tabWidth: 4,
            wrapsLines: true
        )
    ),
    settings: sharedSettings,
    targets: [
        .target(
            name: "UpTilCore",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.zbiljic.uptilcore",
            deploymentTargets: .macOS("14.0"),
            sources: ["Packages/UpTilCore/Sources/**"]
        ),
        .target(
            name: "UpTilCLI",
            destinations: .macOS,
            product: .commandLineTool,
            productName: "uptil",
            bundleId: "com.zbiljic.uptil-cli",
            deploymentTargets: .macOS("14.0"),
            sources: ["Sources/UpTilCLI/**"],
            dependencies: [
                .target(name: "UpTilCore"),
            ],
            settings: cliSettings
        ),
        .target(
            name: "UpTil",
            destinations: .macOS,
            product: .app,
            bundleId: "com.zbiljic.uptil",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .file(path: "Resources/Info.plist"),
            sources: ["Sources/UpTilApp/**"],
            resources: ["Resources/Assets.xcassets"],
            copyFiles: [
                .wrapper(
                    name: "Embed command-line helper",
                    subpath: "Contents/Helpers",
                    files: [
                        .buildProduct(
                            name: "UpTilCLI",
                            codeSignOnCopy: true
                        ),
                    ]
                ),
            ],
            entitlements: .file(path: "Resources/UpTil.entitlements"),
            dependencies: [
                .target(name: "UpTilCore"),
                .target(
                    name: "UpTilCLI",
                    status: .none
                ),
            ],
            settings: appSettings
        ),
        .target(
            name: "UpTilTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.zbiljic.uptiltests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: ["Tests/UpTilAppTests/**"],
            dependencies: [
                .target(name: "UpTil"),
            ],
            settings: appSettings
        ),
    ],
    schemes: [
        .scheme(
            name: "UpTil",
            shared: true,
            buildAction: .buildAction(
                targets: ["UpTil"]
            ),
            testAction: .targets(
                [
                    .testableTarget(
                        target: "UpTilTests",
                        parallelization: .swiftTestingOnly
                    ),
                ],
                options: .options(
                    coverage: true,
                    codeCoverageTargets: ["UpTil", "UpTilCore"]
                )
            ),
            runAction: .runAction(
                executable: "UpTil"
            )
        ),
    ]
)
