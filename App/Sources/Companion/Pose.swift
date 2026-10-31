import CoreGraphics

/// One pose of the stick figure: joint angles in radians, seen from the side with the figure facing right
/// (doc/design/desktop-companion.md › The character › Rig). Limbs at 0 hang straight down; a positive
/// shoulder or hip angle swings the limb forward, a positive elbow or knee bends the lower part forward
/// (so knees bend with negative angles). `front` limbs are drawn over the torso, `back` ones behind it.
struct Pose: Equatable, Sendable {
    /// The hips' height above where they are when standing, in points.
    var hipY: CGFloat = 0
    /// The hips' offset forward, in points (a lunge, a hop forward).
    var hipX: CGFloat = 0
    /// The whole figure tipping forward around the hips (π/2: lying face down, −π/2: on its back).
    var body: CGFloat = 0
    /// The torso leaning forward from the hips.
    var lean: CGFloat = 0
    /// The head tilting forward.
    var neck: CGFloat = 0
    var shoulderBack: CGFloat = 0
    var elbowBack: CGFloat = 0
    var shoulderFront: CGFloat = 0
    var elbowFront: CGFloat = 0
    var hipBack: CGFloat = 0
    var kneeBack: CGFloat = 0
    var hipFront: CGFloat = 0
    var kneeFront: CGFloat = 0

    /// Upright, arms relaxed.
    static let standing = Pose(shoulderBack: -0.08, elbowBack: 0.12, shoulderFront: 0.08, elbowFront: 0.12)

    /// Sitting on something `seatHeight` points high, thighs level, shins hanging, hands on the knees.
    static func sitting(seatHeight: CGFloat, skeleton: Skeleton = .standard) -> Pose {
        Pose(
            hipY: seatHeight - skeleton.legLength, lean: 0.1, shoulderBack: 0.25, elbowBack: 0.9,
            shoulderFront: 0.35, elbowFront: 0.9, hipBack: .pi / 2, kneeBack: -.pi / 2, hipFront: .pi / 2,
            kneeFront: -.pi / 2)
    }

    /// The same pose with the arms swapped and the legs swapped: the second half of a walk cycle.
    var mirrored: Pose {
        var p = self
        (p.shoulderBack, p.shoulderFront) = (shoulderFront, shoulderBack)
        (p.elbowBack, p.elbowFront) = (elbowFront, elbowBack)
        (p.hipBack, p.hipFront) = (hipFront, hipBack)
        (p.kneeBack, p.kneeFront) = (kneeFront, kneeBack)
        return p
    }

    nonisolated(unsafe) static let fields: [WritableKeyPath<Pose, CGFloat>] = [
        \.hipY, \.hipX, \.body, \.lean, \.neck, \.shoulderBack, \.elbowBack, \.shoulderFront, \.elbowFront,
        \.hipBack, \.kneeBack, \.hipFront, \.kneeFront,
    ]

    /// The pose a fraction `t` (0...1) of the way from `a` to `b`.
    static func blend(_ a: Pose, _ b: Pose, _ t: CGFloat) -> Pose {
        var p = a
        for field in fields { p[keyPath: field] = a[keyPath: field] + (b[keyPath: field] - a[keyPath: field]) * t }
        return p
    }

    /// The pose at `t` (0...1) along evenly spaced keyframes, eased in and out between each pair.
    static func sample(_ keyframes: [Pose], at t: CGFloat) -> Pose {
        guard keyframes.count > 1 else { return keyframes.first ?? .standing }
        let scaled = min(max(t, 0), 1) * CGFloat(keyframes.count - 1)
        let i = min(Int(scaled), keyframes.count - 2)
        let f = scaled - CGFloat(i)
        return blend(keyframes[i], keyframes[i + 1], f * f * (3 - 2 * f))
    }
}

/// The figure's bone lengths, and where its joints are for a pose (forward kinematics, the same math the
/// layers do). Coordinates: points, y up, the floor at y = 0, the standing hips at x = 0, facing right.
struct Skeleton: Equatable, Sendable {
    var torso: CGFloat = 13
    var headRadius: CGFloat = 4.5
    var upperArm: CGFloat = 8
    var forearm: CGFloat = 8
    var thigh: CGFloat = 10
    var shin: CGFloat = 10
    var lineWidth: CGFloat = 2

    static let standard = Skeleton()

    var legLength: CGFloat { thigh + shin }
    /// Standing height, from the floor to the top of the head.
    var height: CGFloat { legLength + torso + headRadius * 2 }

    struct Points: Equatable {
        var hips, neck, head: CGPoint
        var elbowBack, handBack, elbowFront, handFront: CGPoint
        var kneeBack, footBack, kneeFront, footFront: CGPoint
    }

    func points(_ p: Pose) -> Points {
        let hips = CGPoint(x: p.hipX, y: legLength + p.hipY)
        // Layer rotations are counterclockwise; the torso points up, the limbs down.
        let root = -p.body
        let chest = root - p.lean
        let neck = hips + Self.up(chest) * torso
        let head = neck + Self.up(chest - p.neck) * headRadius
        func arm(_ shoulder: CGFloat, _ elbow: CGFloat) -> (CGPoint, CGPoint) {
            let e = neck + Self.down(chest + shoulder) * upperArm
            return (e, e + Self.down(chest + shoulder + elbow) * forearm)
        }
        func leg(_ hip: CGFloat, _ knee: CGFloat) -> (CGPoint, CGPoint) {
            let k = hips + Self.down(root + hip) * thigh
            return (k, k + Self.down(root + hip + knee) * shin)
        }
        let (eb, hb) = arm(p.shoulderBack, p.elbowBack)
        let (ef, hf) = arm(p.shoulderFront, p.elbowFront)
        let (kb, fb) = leg(p.hipBack, p.kneeBack)
        let (kf, ff) = leg(p.hipFront, p.kneeFront)
        return Points(
            hips: hips, neck: neck, head: head, elbowBack: eb, handBack: hb, elbowFront: ef, handFront: hf,
            kneeBack: kb, footBack: fb, kneeFront: kf, footFront: ff)
    }

    /// `pose` with both arms reaching for `hand` (the back hand `backOffset` further back), elbows bent
    /// out behind (`elbowsBehind`) or in front. Out-of-reach targets get a straight arm pointing at them.
    func reaching(_ pose: Pose, hand: CGPoint, elbowsBehind: Bool, backOffset: CGFloat = 1) -> Pose {
        var p = pose
        let neck = points(pose).neck
        let chest = -pose.body - pose.lean
        (p.shoulderFront, p.elbowFront) = Self.solve(
            from: neck, to: hand, upper: upperArm, lower: forearm, parent: chest, behind: elbowsBehind)
        (p.shoulderBack, p.elbowBack) = Self.solve(
            from: neck, to: CGPoint(x: hand.x - backOffset, y: hand.y), upper: upperArm, lower: forearm, parent: chest,
            behind: elbowsBehind)
        return p
    }

    /// Each arm reaching for its own target, with the elbows out to the sides: seen from the front, the front
    /// arm is on the screen's right and its elbow bends clockwise of the line from the shoulder to the hand,
    /// the back arm's counterclockwise.
    func reachingOut(_ pose: Pose, front: CGPoint, back: CGPoint) -> Pose {
        var p = pose
        let neck = points(pose).neck
        let chest = -pose.body - pose.lean
        (p.shoulderFront, p.elbowFront) = Self.solve(
            from: neck, to: front, upper: upperArm, lower: forearm, parent: chest, clockwise: true)
        (p.shoulderBack, p.elbowBack) = Self.solve(
            from: neck, to: back, upper: upperArm, lower: forearm, parent: chest, clockwise: false)
        return p
    }

    /// Two-bone inverse kinematics: the joint angles (relative to a parent turned `parent`) that put the end
    /// of a chain from `origin` at `target`, with the middle joint behind (smaller x) or in front.
    static func solve(
        from origin: CGPoint, to target: CGPoint, upper: CGFloat, lower: CGFloat, parent: CGFloat, behind: Bool
    ) -> (CGFloat, CGFloat) {
        let (ccw, cw) = solutions(from: origin, to: target, upper: upper, lower: lower)
        let middleX = { (angle: CGFloat) in origin.x + sin(angle) * upper }
        let first = behind == (middleX(ccw.0) < middleX(cw.0)) ? ccw : cw
        return (first.0 - parent, first.1)
    }

    /// The same, with the middle joint clockwise or counterclockwise of the line from `origin` to `target`.
    static func solve(
        from origin: CGPoint, to target: CGPoint, upper: CGFloat, lower: CGFloat, parent: CGFloat, clockwise: Bool
    ) -> (CGFloat, CGFloat) {
        let (ccw, cw) = solutions(from: origin, to: target, upper: upper, lower: lower)
        let first = clockwise ? cw : ccw
        return (first.0 - parent, first.1)
    }

    /// Both solutions as (upper bone's world angle, lower bone's angle relative to it): the middle joint
    /// counterclockwise of the line to the target, then clockwise.
    private static func solutions(
        from origin: CGPoint, to target: CGPoint, upper: CGFloat, lower: CGFloat
    ) -> ((CGFloat, CGFloat), (CGFloat, CGFloat)) {
        let dx = target.x - origin.x, dy = target.y - origin.y
        let d = min(max(hypot(dx, dy), abs(upper - lower) + 0.001), upper + lower - 0.001)
        // World angle of the target in the limbs' convention: 0 = straight down, counterclockwise.
        let theta = atan2(dx, -dy)
        let alpha = acos(min(max((upper * upper + d * d - lower * lower) / (2 * upper * d), -1), 1))
        let beta = acos(min(max((upper * upper + lower * lower - d * d) / (2 * upper * lower), -1), 1))
        return ((theta + alpha, -(.pi - beta)), (theta - alpha, .pi - beta))
    }

    /// (0, 1) and (0, −1) turned counterclockwise by `angle`.
    static func up(_ angle: CGFloat) -> CGPoint { CGPoint(x: -sin(angle), y: cos(angle)) }
    static func down(_ angle: CGFloat) -> CGPoint { CGPoint(x: sin(angle), y: -cos(angle)) }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
}
