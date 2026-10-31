import CoreGraphics
import QuartzCore

/// The figure's moves: pose loops and how long they take (doc/design/desktop-companion.md › Animations).
/// Loops end with their first pose, as `StickFigure.animate` expects.
enum Moves {
    // MARK: Workouts

    /// Seconds per keyframe step in an activity's intro and outro.
    static let transitionStep: CFTimeInterval = 0.5

    /// Squat, clean the barbell to the shoulders, then push presses: dip, press overhead, hold, lower.
    static func weightLifting(_ s: Skeleton = .standard) -> Activity {
        func rack(_ p: Pose) -> Pose {
            let neck = s.points(p).neck
            // In front of the chest, clear of the head.
            return s.reaching(p, hand: CGPoint(x: neck.x + 7, y: neck.y - 3), elbowsBehind: false)
        }
        let standing = grounded(Pose(), s)
        let held = rack(standing)
        let dip = rack(grounded(Pose(hipBack: 0.35, kneeBack: -0.7, hipFront: 0.35, kneeFront: -0.7), s))
        let overhead: Pose = {
            let neck = s.points(standing).neck
            // Straight up, a little in front of the head.
            return s.reaching(standing, hand: CGPoint(x: neck.x + 4, y: neck.y + s.upperArm + s.forearm - 1.5), elbowsBehind: false)
        }()
        let squat: Pose = {
            let p = grounded(Pose(lean: 0.7, hipBack: 1.3, kneeBack: -2.3, hipFront: 1.3, kneeFront: -2.3), s)
            return s.reaching(p, hand: CGPoint(x: s.points(p).neck.x + 2, y: 4), elbowsBehind: false)
        }()
        return Activity(
            name: "weight lifting", intro: [squat, held], loop: [held, dip, overhead, overhead, held], rep: 3,
            outro: [squat, .standing], prop: .barbell)
    }

    /// Down into a plank, then push-ups: feet and hands stay planted while the body lowers and rises.
    static func pushUps(_ s: Skeleton = .standard) -> Activity {
        let feetX: CGFloat = -18
        // The body in one line from the feet, `angle` above the floor.
        func plank(_ angle: CGFloat) -> Pose {
            Pose(hipY: s.legLength * sin(angle) - s.legLength, hipX: feetX + s.legLength * cos(angle), body: .pi / 2 - angle)
        }
        let handX = s.points(plank(0.5)).neck.x + 1
        let up = s.reaching(plank(0.5), hand: CGPoint(x: handX, y: 0), elbowsBehind: true)
        let down = s.reaching(plank(0.2), hand: CGPoint(x: handX, y: 0), elbowsBehind: true)
        let crouch: Pose = {
            let p = grounded(Pose(lean: 0.9, hipBack: 1.4, kneeBack: -2.4, hipFront: 1.4, kneeFront: -2.4), s)
            return s.reaching(p, hand: CGPoint(x: s.points(p).neck.x + 6, y: 0), elbowsBehind: true)
        }()
        return Activity(name: "push-ups", intro: [crouch, up], loop: [up, down, up], rep: 1.6, outro: [crouch, .standing], prop: nil)
    }

    /// Jumping jacks, seen from the front: hop, landing with legs apart and arms up, hop back together.
    static func jumpingJacks(_ s: Skeleton = .standard) -> Activity {
        let closed = grounded(Pose(shoulderBack: -0.12, elbowBack: 0.1, shoulderFront: 0.12, elbowFront: -0.1), s)
        let open = grounded(Pose(
            shoulderBack: -(.pi - 0.5), elbowBack: 0.15, shoulderFront: .pi - 0.5, elbowFront: -0.15,
            hipBack: -0.32, hipFront: 0.32), s)
        let air = grounded(Pose.blend(closed, open, 0.5), s, lift: 3)
        return Activity(
            name: "jumping jacks", intro: [closed], loop: [closed, air, open, air, closed], rep: 0.8,
            outro: [.standing], prop: nil)
    }

    /// The pull-up bar's height above the floor, and its posts' distance from the middle.
    static let barHeight: CGFloat = 45
    static let barHalfWidth: CGFloat = 14

    /// Pull-ups on a bar, seen from the front: reach up and hang, pull until the chin is over the bar, lower.
    static func pullUps(_ s: Skeleton = .standard) -> Activity {
        let grip: CGFloat = 6
        func holding(_ p: Pose) -> Pose {
            s.reachingOut(p, front: CGPoint(x: grip, y: barHeight), back: CGPoint(x: -grip, y: barHeight))
        }
        let legs = Pose(hipBack: -0.06, kneeBack: -0.35, hipFront: 0.06, kneeFront: -0.35)
        let reach = holding(grounded(Pose(), s))
        var hangBase = legs
        hangBase.hipY = 1.5
        let hang = holding(hangBase)
        var upBase = legs
        // The chin over the bar.
        upBase.hipY = barHeight + 1 - (s.legLength + s.torso)
        let up = holding(upBase)
        return Activity(
            name: "pull-ups", intro: [.standing, reach, hang], loop: [hang, up, up, hang], rep: 2, outro: [reach, .standing],
            prop: .pullUpBar)
    }

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

/// A workout or other repeated move: into it, reps of a loop, and back to standing.
struct Activity {
    var name: String
    /// Keyframes from wherever the figure is into the loop's first pose (the last one).
    var intro: [Pose]
    /// One rep, ending with its first pose.
    var loop: [Pose]
    /// Seconds per rep.
    var rep: CFTimeInterval
    /// Keyframes from the loop back to standing.
    var outro: [Pose]
    /// Shown from the end of the intro's first step to the start of the outro's last one.
    var prop: Prop?

    var introDuration: CFTimeInterval { Moves.transitionStep * Double(intro.count) }
    var outroDuration: CFTimeInterval { Moves.transitionStep * Double(outro.count) }

    /// How long `reps` reps take, intro and outro included.
    func duration(reps: Int) -> CFTimeInterval { introDuration + rep * Double(reps) + outroDuration }
}

extension StickFigure {
    /// Plays `activity` for `reps` reps, then stands and runs `done` (unless stopped).
    func perform(_ activity: Activity, reps: Int, done: @escaping @MainActor () -> Void = {}) {
        let step = Moves.transitionStep
        animate([presentedPose()] + activity.intro, duration: activity.introDuration)
        if let prop = activity.prop {
            after(activity.intro.count > 1 ? step : 0) { [weak self] in self?.show(prop) }
        }
        after(activity.introDuration) { [weak self] in
            guard let self else { return }
            animate(activity.loop, duration: activity.rep, repeats: true)
            after(activity.rep * Double(max(1, reps))) { [weak self] in
                guard let self else { return }
                animate([presentedPose()] + activity.outro, duration: activity.outroDuration)
                after(max(0, activity.outroDuration - step)) { [weak self] in
                    self?.hideProps()
                    self?.after(step) { [weak self] in
                        self?.apply(.standing)
                        done()
                    }
                }
            }
        }
    }

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
