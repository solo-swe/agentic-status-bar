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

    // MARK: Wave

    /// Seconds per keyframe of the wave loop.
    static let waveStep: CFTimeInterval = 0.25

    /// Facing you: raise the front arm, swing the forearm 3 times, lower it, wait about 2 s; one loop.
    static func wave(_ s: Skeleton = .standard) -> [Pose] {
        let rest = grounded(Pose(shoulderBack: -0.12, elbowBack: 0.1, shoulderFront: 0.12, elbowFront: -0.1), s)
        func arm(_ shoulder: CGFloat, _ elbow: CGFloat) -> Pose {
            var p = rest
            (p.shoulderFront, p.elbowFront) = (shoulder, elbow)
            return p
        }
        let half = arm(1.3, 0.6)
        let raised = arm(2.2, 0.0)
        let (out, inward) = (arm(2.2, -0.7), arm(2.2, 0.7))
        let swings = Array(repeating: [out, inward], count: 3).flatMap { $0 }
        let wait = Array(repeating: rest, count: Int(2 / waveStep))
        return [rest, half, raised] + swings + [raised, half] + wait + [rest]
    }

    /// The speech bubble's glyph for why a session waits.
    static func bubbleGlyph(reason: String?) -> String {
        reason == "question" ? "?" : "!"
    }

    /// Standing, catching its breath between activities; one breath.
    static func resting(_ s: Skeleton = .standard) -> [Pose] {
        var inhale = Pose.standing
        inhale.lean = -0.04
        inhale.shoulderBack -= 0.06
        inhale.shoulderFront += 0.06
        return [.standing, inhale, .standing]
    }

    // MARK: Other states

    /// Seconds per keyframe of the head scratch and the reading loops.
    static let idleStep: CFTimeInterval = 0.25

    /// No activity: puzzled, a hand scratching the side of the head, head tilted; one loop with a pause.
    static func scratching(_ s: Skeleton = .standard) -> [Pose] {
        var rest = grounded(Pose.standing, s)
        rest.neck = 0.18
        let head = s.points(rest).head
        // The fingers at the side of the head, just outside its circle.
        func scratch(_ dy: CGFloat) -> Pose {
            s.reachingFront(rest, hand: CGPoint(x: head.x + s.headRadius + 1.5, y: head.y + dy), elbowBehind: false)
        }
        let (up, down) = (scratch(1.5), scratch(-1))
        let pause = Array(repeating: rest, count: Int(1.5 / idleStep))
        return [rest, up, down, up, down, up, down, up] + pause + [rest]
    }

    /// Only muted sessions: sitting on the bed reading a book held in front, a page turned now and then.
    static func reading(_ s: Skeleton = .standard) -> [Pose] {
        var sit = sittingOnBed(s)
        sit.neck = 0.5
        let neck = s.points(sit).neck
        // The book on the lap, out in front, the head bent over it.
        let read = s.reaching(sit, hand: CGPoint(x: neck.x + 9, y: neck.y - 10), elbowsBehind: false, backOffset: 2)
        // The back hand sweeps across to turn the page.
        var turn = read
        (turn.shoulderBack, turn.elbowBack) = Skeleton.solve(
            from: neck, to: CGPoint(x: neck.x + 11, y: neck.y - 6), upper: s.upperArm, lower: s.forearm,
            parent: -sit.body - sit.lean, behind: false)
        return Array(repeating: read, count: 24) + [turn, turn, read]
    }

    /// A warning: standing, holding a little sign with a wrench up in front, upper arm level and forearm
    /// upright (the sign fits under the strip's top that way), swaying a bit; one loop.
    static func holdingSign(_ s: Skeleton = .standard) -> [Pose] {
        func hold(_ sway: CGFloat) -> Pose {
            // The forearm's world angle is shoulder + elbow − lean; π points it straight up.
            let shoulder: CGFloat = 1.6
            return grounded(Pose(
                lean: sway, shoulderBack: -0.12, elbowBack: 0.1, shoulderFront: shoulder,
                elbowFront: .pi - shoulder + sway), s)
        }
        return [hold(-0.04), hold(0.04), hold(-0.04)]
    }

    /// The sign's stick and board, up from the hand.
    static let signStick: CGFloat = 4
    static let signBoard = CGSize(width: 16, height: 9)

    /// The bubble's glyph when a session has gone quiet.
    static let puzzledGlyph = "•••"

    // MARK: Bed

    /// Seconds per breath (asleep or resting), and per rising *z*.
    static let breath: CFTimeInterval = 4
    static let zzzCycle: CFTimeInterval = 3

    /// On its back on the mattress, head toward the headboard (behind it), one knee up, arms along the body.
    static func lying(_ s: Skeleton = .standard) -> Pose {
        // The head a little raised by the pillow; the heels rest on the mattress.
        let pose = Pose(
            body: -.pi / 2 + 0.14, shoulderBack: -0.05, elbowBack: 0.1, shoulderFront: 0.05, elbowFront: 0.15,
            hipBack: 0.05, hipFront: 0.45, kneeFront: -0.8)
        return grounded(pose, s, lift: StripLayout.mattressHeight + s.lineWidth / 2)
    }

    /// One breath lying down: the chest and head rise a little and settle.
    static func breathing(_ s: Skeleton = .standard) -> [Pose] {
        let rest = lying(s)
        var inhale = rest
        inhale.lean -= 0.05
        inhale.neck -= 0.04
        return [rest, inhale, rest]
    }

    /// Sitting on the bed's edge.
    static func sittingOnBed(_ s: Skeleton = .standard) -> Pose {
        .sitting(seatHeight: StripLayout.mattressHeight, skeleton: s)
    }

    /// Sitting on the bed's edge for a while, with a tilt of the head now and then; one loop.
    static func sittingIdle(_ s: Skeleton = .standard) -> [Pose] {
        let sit = sittingOnBed(s)
        var tilt = sit
        tilt.neck = 0.25
        return Array(repeating: sit, count: 10) + [tilt, tilt, sit]
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

    /// Waves at you over and over, with `glyph` (**!** or **?**) in a bubble of `color`, until stopped.
    func wave(_ glyph: String, color: CGColor) {
        let loop = Moves.wave(skeleton)
        animate([presentedPose(), loop[0]], duration: Moves.transitionStep)
        say(glyph, color: color)
        after(Moves.transitionStep) { [weak self] in
            self?.animate(loop, duration: Moves.waveStep * Double(loop.count - 1), repeats: true)
        }
    }

    /// Scratches its head, puzzled, with `Moves.puzzledGlyph` in a bubble of `color`, until stopped.
    func scratchHead(color: CGColor) {
        let loop = Moves.scratching(skeleton)
        say(Moves.puzzledGlyph, color: color)
        animate([presentedPose(), loop[0]], duration: Moves.transitionStep)
        after(Moves.transitionStep) { [weak self] in
            self?.animate(loop, duration: Moves.idleStep * Double(loop.count - 1), repeats: true)
        }
    }

    /// Holds up a sign with a wrench, swaying a little, until stopped.
    func holdSign() {
        let loop = Moves.holdingSign(skeleton)
        animate([presentedPose(), loop[0]], duration: Moves.transitionStep)
        after(Moves.transitionStep) { [weak self] in
            guard let self else { return }
            show(.sign)
            animate(loop, duration: 3, repeats: true, smooth: true)
        }
    }

    /// Walks to the bed at `x`, sits on its edge facing `facing` and reads a book, until stopped.
    func read(at x: CGFloat, facing bedFacing: Facing) {
        walk(to: x) { [weak self] in
            guard let self else { return }
            facing = bedFacing
            let loop = Moves.reading(skeleton)
            animate([presentedPose(), Moves.sittingOnBed(skeleton), loop[0]], duration: 2 * Moves.transitionStep)
            after(2 * Moves.transitionStep) { [weak self] in
                guard let self else { return }
                show(.book)
                animate(loop, duration: Moves.idleStep * Double(loop.count - 1), repeats: true)
            }
        }
    }

    /// Walks to the bed at `x` (the hips' spot on it), sits down, lies down facing `facing` (head on the
    /// pillow), and sleeps: breathing, with *z*s rising, until stopped.
    func sleep(at x: CGFloat, facing bedFacing: Facing) {
        walk(to: x) { [weak self] in
            guard let self else { return }
            facing = bedFacing
            let sit = Moves.sittingOnBed(skeleton), lie = Moves.lying(skeleton)
            animate([presentedPose(), sit, lie], duration: 2 * Moves.transitionStep)
            after(2 * Moves.transitionStep) { [weak self] in
                guard let self else { return }
                show(.zzz)
                // Breathing is slow: smooth, not cut into frames.
                animate(Moves.breathing(skeleton), duration: Moves.breath, repeats: true, smooth: true)
            }
        }
    }

    /// Walks to the bed at `x` and sits on its edge facing `facing`, tilting its head now and then, until stopped.
    func sit(at x: CGFloat, facing bedFacing: Facing) {
        walk(to: x) { [weak self] in
            guard let self else { return }
            facing = bedFacing
            let loop = Moves.sittingIdle(skeleton)
            animate([presentedPose(), loop[0]], duration: Moves.transitionStep)
            after(Moves.transitionStep) { [weak self] in
                self?.animate(loop, duration: 0.5 * Double(loop.count - 1), repeats: true)
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
