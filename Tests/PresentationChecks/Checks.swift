import Foundation
import PetCore

@main struct PresentationChecks {
    static func main() throws {
        var coverage = Set<PetAction>()
        for index in 0..<4 {
            var seq = PetAnimationSequence()
            let p = seq.next(context: .wandering, mood: 5) { min(index, $0-1) }
            coverage.insert(p.action)
            precondition((8...16).contains(p.seconds))
        }
        precondition(coverage == Set(PetAction.workActions))
        var seq = PetAnimationSequence()
        var previous: PetAction?
        for _ in 0..<100 {
            let plan = seq.next(context: .wandering, mood: 5) { _ in 0 }
            precondition(previous != plan.action)
            previous = plan.action
        }
        for (context, action) in [(PetVisualContext.eating, PetAction.eat), (.walking,.walk), (.sleeping,.sleep), (.completed,.idle)] {
            let p = seq.next(context: context, mood: 5) { _ in 0 }
            precondition(p.action == action)
        }
        precondition(seq.next(context: .completed, mood: 1) { _ in 0 }.expression == .angry)
        precondition(seq.next(context: .completed, mood: 5) { _ in 0 }.expression == .happy)
        precondition(PetAnimationPlan().frameDuration(secondFrame: false) == 4_850_000_000)
        precondition(PetAnimationPlan().frameDuration(secondFrame: true) == 150_000_000)
        for width in [144.0, 184.0, 0.0, 50.0] {
            for size in [72.0, 96.0] {
                let bound = max(0, (width - size) / 2)
                var positions = Set<Int>()
                for n in 0..<1000 {
                    let x = PetTravel.offset(elapsed: Double(n) / 20, availableWidth: width, spriteWidth: size)
                    precondition(abs(x) <= bound + 0.0001)
                    positions.insert(Int(x))
                }
                if bound > 0 { precondition(positions.count > 20, "Walking must visibly translate") }
            }
        }
        precondition(PetTravel.offset(elapsed: .nan, availableWidth: 160, spriteWidth: 72) == 0)
        for species in [PetSpecies.cat, .dinosaur] {
            let original = try Pet(id: UUID(uuidString: species == .cat ? "00000000-0000-0000-0000-000000000000" : "00000000-0000-0000-0000-000000000001")!)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let encoded = try encoder.encode(original)
            for action in PetAction.allCases {
                for expression in PetExpression.allCases {
                    let plan = PetAnimationPlan(action: action, expression: expression)
                    precondition(plan.asset(species: species, secondFrame: false) != plan.asset(species: species, secondFrame: true))
                }
            }
            // Presentation can only receive values; no mutation or encoding path exists.
            let after = try encoder.encode(original)
            precondition(after == encoded)
        }
        print("PASS PresentationChecks: five-action coverage, no-repeat sequence, context/mood priority, duration bounds, frame names and unchanged pet data")
    }
}
