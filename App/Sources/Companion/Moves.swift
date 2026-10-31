import CoreGraphics
import QuartzCore

/// The figure's moves: pose loops and how long they take (doc/design/desktop-companion.md › Animations).
/// Loops end with their first pose, as `StickFigure.animate` expects.
enum Moves {
    // MARK: Walk

    /// Seconds per walk cycle (two steps).
    static let walkCycle: CFTimeInterval = 1

    /// Contact, down, passing and up of the front leg's step (after Richard Williams' walk); the back
    /// leg's step is the same, mirrored. Hip heights are set so the supporting foot stays on the floor.
    static func walk(_ s: Skeleton = .standard) -> [Pose] {
        let contact = Pose(
            lean: 0.05, shoulderBack: 0.35, elbowBack: 0.35, shoulderFront: -0.35, elbowFront: 0.25,
            hipBack: -0.38, kneeBack: -0.15, hipFront: 0.42, kneeFront: -0.05)
        let down = Pose(
            lean: 0.07, shoulderBack: 0.25, elbowBack: 0.3, shoulderFront: -0.25, elbowFront: 0.25,
            hipBack: -0.32, kneeBack: -0.45, hipFront: 0.25, kneeFront: -0.35)
        let passing = Pose(
            lean: 0.05, shoulderBack: 0, elbowBack: 0.2, shoulderFront: 0, elbowFront: 0.2,
            hipBack: 0.15, kneeBack: -1.0, hipFront: 0, kneeFront: -0.08)
        let up = Pose(
            lean: 0.04, shoulderBack: -0.2, elbowBack: 0.2, shoulderFront: 0.2, elbowFront: 0.3,
            hipBack: 0.35, kneeBack: -0.55, hipFront: -0.25, kneeFront: 0)
        // Down is the lowest point (its bent knee lowers the hips) and up the highest (on the toes).
        let step = [grounded(contact, s), grounded(down, s), grounded(passing, s), grounded(up, s, lift: 0.8)]
        let cycle = step + step.map(\.mirrored)
        return cycle + [cycle[0]]
    }

    /// How far a step reaches: the distance between the feet at contact.
    static func stride(_ s: Skeleton = .standard) -> CGFloat {
        let p = s.points(walk(s)[0])
        return abs(p.footFront.x - p.footBack.x)
    }

    /// Walking speed in points a second, so the feet don't slide: two strides per cycle.
    static func walkSpeed(_ s: Skeleton = .standard) -> CGFloat {
        2 * stride(s) / CGFloat(walkCycle)
    }

    /// `pose` with its hip height set so the lower foot touches the floor, then raised by `lift` points.
    static func grounded(_ pose: Pose, _ s: Skeleton = .standard, lift: CGFloat = 0) -> Pose {
        var p = pose
        p.hipY = 0
        let points = s.points(p)
        p.hipY = -min(points.footBack.y, points.footFront.y) + lift
        return p
    }
}

extension StickFigure {
    /// Walks to `x` along the strip, turning to face the way, then stands and runs `done` (unless stopped).
    func walk(to x: CGFloat, done: @escaping @MainActor () -> Void = {}) {
        let from = presentedX
        guard abs(x - from) > 0.5 else {
            apply(.standing)
            done()
            return
        }
        stop()
        facing = x > from ? .right : .left
        animate(Moves.walk(skeleton), duration: Moves.walkCycle, repeats: true)
        travel(to: x, speed: Moves.walkSpeed(skeleton)) { [weak self] in
            self?.apply(.standing)
            done()
        }
    }

    /// Strolls about `range` for about `seconds`: walks to a spot, looks around for a moment, walks on.
    /// `random` gives numbers in 0..<1 (injectable for tests).
    func stroll(
        for seconds: TimeInterval, in range: ClosedRange<CGFloat>, random: @escaping () -> Double = { .random(in: 0..<1) },
        done: @escaping @MainActor () -> Void = {}
    ) {
        let end = CACurrentMediaTime() + seconds
        func next() {
            guard CACurrentMediaTime() < end else {
                apply(.standing)
                done()
                return
            }
            walk(to: Self.strollTarget(from: presentedX, in: range, random: random())) { [weak self] in
                // A short pause between walks keeps it calm.
                self?.after(0.6 + 1.2 * random()) { next() }
            }
        }
        next()
    }

    /// A spot in `range` at least a third of the range away from `x` (so every walk is a real one).
    static func strollTarget(from x: CGFloat, in range: ClosedRange<CGFloat>, random: Double) -> CGFloat {
        let width = range.upperBound - range.lowerBound
        let gap = width / 3
        // Pick along the parts of the range that are far enough from x, as one stretch.
        let leftLength = max(0, (x - gap) - range.lowerBound)
        let rightLength = max(0, range.upperBound - (x + gap))
        let pick = CGFloat(random) * (leftLength + rightLength)
        if leftLength + rightLength <= 0 { return x < range.lowerBound + width / 2 ? range.upperBound : range.lowerBound }
        return pick < leftLength ? range.lowerBound + pick : x + gap + (pick - leftLength)
    }
}
