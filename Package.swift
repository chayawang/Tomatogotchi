// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Tomatogotchi", platforms: [.macOS(.v13)],
    products: [.executable(name: "Tomatogotchi", targets: ["Tomatogotchi"])],
    targets: [
        .target(name: "PetCore"),
        .target(name: "DesktopCore"),
        .target(name: "CareCore"),
        .target(name: "CareFlow", dependencies: ["CareCore", "AdoptionFlow", "PetCore"]),
        .target(name: "AdoptionFlow", dependencies: ["PetCore", "CareCore"]),
        .executableTarget(name: "Tomatogotchi", dependencies: ["PetCore", "AdoptionFlow", "DesktopCore", "CareCore", "CareFlow"], resources: [.process("Resources")]),
        .executableTarget(name: "MemorialChecks", dependencies: ["PetCore", "AdoptionFlow"], path: "Tests/MemorialChecks"),
        .executableTarget(name: "PresentationChecks", dependencies: ["PetCore"], path: "Tests/PresentationChecks"),
        .executableTarget(name: "CoreChecks", dependencies: ["PetCore"], path: "Tests/CoreChecks"),
        .executableTarget(name: "FlowChecks", dependencies: ["PetCore", "AdoptionFlow"], path: "Tests/FlowChecks"),
        .executableTarget(name: "SessionChecks", dependencies: ["DesktopCore"], path: "Tests/SessionChecks"),
        .executableTarget(name: "DesktopChecks", dependencies: ["DesktopCore"], path: "Tests/DesktopChecks"),
        .executableTarget(name: "CareFlowChecks", dependencies: ["CareCore", "CareFlow"], path: "Tests/CareFlowChecks"),
        .executableTarget(name: "CareChecks", dependencies: ["CareCore"], path: "Tests/CareChecks"),
        .executableTarget(name: "ReminderChecks", dependencies: ["CareCore"], path: "Tests/ReminderChecks"),
        .executableTarget(name: "SurvivalChecks", dependencies: ["PetCore", "AdoptionFlow", "CareCore", "CareFlow"], path: "Tests/SurvivalChecks"),
        .executableTarget(name: "GrowthChecks", dependencies: ["PetCore", "CareCore", "AdoptionFlow"], path: "Tests/GrowthChecks")
    ]
)
