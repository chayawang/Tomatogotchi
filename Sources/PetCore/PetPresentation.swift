import Foundation

/// Ephemeral appearance only: never encoded into pet/care storage.
public enum PetAction: String, CaseIterable, Sendable {
    case idle, walk, sleep, play, eat
    public static let workActions: [PetAction] = [.idle, .walk, .sleep, .play]
}
public enum PetExpression: String, CaseIterable, Sendable { case neutral, happy, angry, joyful }
public enum PetVisualContext: String, Sendable { case wandering, eating, walking, sleeping, completed }

public struct PetAnimationPlan: Equatable, Sendable {
    public let action: PetAction
    public let expression: PetExpression
    public let seconds: Int
    public init(action: PetAction = .idle, expression: PetExpression = .neutral, seconds: Int = 8) {
        self.action = action; self.expression = expression; self.seconds = seconds
    }
    public func frameDuration(secondFrame: Bool) -> UInt64 {
        if action == .idle { return secondFrame ? 150_000_000 : 4_850_000_000 }
        return action == .sleep ? 1_000_000_000 : 400_000_000
    }
    public func asset(species: PetSpecies, secondFrame: Bool) -> String {
        "\(species.rawValue)-\(action.rawValue)-\(expression.rawValue)-\(secondFrame ? 1 : 0)"
    }
}

public struct PetAnimationSequence {
    public private(set) var previous: PetAction?
    public init() { }
    /// draw receives an exclusive upper bound. Inject it for deterministic verification.
    public mutating func next(context: PetVisualContext, mood: Int, draw: (Int) -> Int) -> PetAnimationPlan {
        func sample(_ upper: Int) -> Int { min(upper - 1, max(0, draw(upper))) }
        let action: PetAction
        switch context {
        case .eating: action = .eat
        case .walking: action = .walk
        case .sleeping: action = .sleep
        case .completed: action = .idle
        case .wandering:
            let options = PetAction.workActions.filter { $0 != previous }
            action = options[sample(options.count)]
        }
        let expression: PetExpression
        if mood <= 2 { expression = .angry }
        else if context == .completed || context == .eating { expression = .happy }
        else if action == .play { expression = .joyful }
        else { expression = [PetExpression.neutral, .happy, .joyful][sample(3)] }
        previous = action
        return PetAnimationPlan(action: action, expression: expression, seconds: 8 + sample(9))
    }
}


/// A deterministic reflected path. Never stores pet/care state or follows wall-clock jumps.
public enum PetTravel {
    public static func offset(elapsed: Double, availableWidth: Double, spriteWidth: Double, speed: Double = 18) -> Double {
        guard elapsed.isFinite, availableWidth.isFinite, spriteWidth.isFinite, speed.isFinite,
              elapsed >= 0, spriteWidth > 0, speed > 0 else { return 0 }
        let limit = max(0, (availableWidth - spriteWidth) / 2)
        guard limit > 0 else { return 0 }
        let phase = (elapsed.truncatingRemainder(dividingBy: 4 * limit / speed) * speed + limit)
            .truncatingRemainder(dividingBy: 4 * limit)
        return phase <= 2 * limit ? phase - limit : 3 * limit - phase
    }
}
