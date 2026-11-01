import AppKit
import QuartzCore

/// The stick figure as a Core Animation skeleton (doc/design/desktop-companion.md › Rig). Every bone is a
/// zero-size layer at its joint that draws its own line; the bones it carries sit at its tip, so turning
/// a bone turns everything below it. Animations are keyframes per joint, played by the render server.
@MainActor
final class StickFigure {
    enum Bone: CaseIterable {
        case hips, torso, head, upperArmBack, forearmBack, upperArmFront, forearmFront
        case thighBack, shinBack, thighFront, shinFront
    }

    enum Facing { case right, left }

    let skeleton: Skeleton
    /// Its position is the point on the floor under the standing hips.
    let layer = CALayer()
    private(set) var bones: [Bone: CALayer] = [:]
    private var shapes: [CAShapeLayer] = []
    /// Props on show (Props.swift).
    var props: [Prop: CALayer] = [:]
    /// The pose the model layers hold (the last one applied, or where the last animation ends).
    private(set) var pose = Pose.standing

    /// Back limbs are drawn a little lighter, so a side view reads which leg is which.
    static let backOpacity: Float = 0.6
    /// The animation key of the moves `animate` plays.
    static let moveKey = "move"

    var facing: Facing = .right {
        didSet {
            withoutActions {
                layer.transform = CATransform3DMakeScale(facing == .left ? -1 : 1, 1, 1)
                // Text in the bubble and the z's are flipped back.
                props[.bubble]?.transform = layer.transform
                for z in props[.zzz]?.sublayers ?? [] { z.transform = layer.transform }
            }
        }
    }

    var color: CGColor = NSColor.labelColor.cgColor {
        didSet {
            for shape in shapes {
                shape.strokeColor = color
                if shape.fillColor != nil { shape.fillColor = color }
            }
            for z in props[.zzz]?.sublayers ?? [] { (z as? CATextLayer)?.foregroundColor = color }
            for follower in followers { follower.color = color }
        }
    }

    // MARK: Followers

    /// Tiny figures behind this one, one per running subagent: they move with it (they are part of its
    /// layer) and copy its moves a moment later.
    private(set) var followers: [StickFigure] = []
    static let maxFollowers = 3
    static let followerScale: CGFloat = 0.55
    /// How far behind each follower walks, and how much later it copies a move.
    static let followerSpacing: CGFloat = 13
    static let followerDelay: CFTimeInterval = 0.18

    /// Shows `count` followers (at most `maxFollowers`), standing in the current pose until the next move.
    func setFollowers(_ count: Int) {
        let count = min(max(count, 0), Self.maxFollowers)
        guard count != followers.count else { return }
        withoutActions {
            while followers.count > count { followers.removeLast().layer.removeFromSuperlayer() }
            while followers.count < count {
                let follower = StickFigure(skeleton: skeleton)
                follower.color = color
                let k = Self.followerScale
                follower.layer.transform = CATransform3DMakeScale(k, k, 1)
                follower.layer.position = CGPoint(x: -Self.followerSpacing * CGFloat(followers.count + 1) - 6, y: 0)
                follower.apply(pose)
                // Behind the figure.
                layer.insertSublayer(follower.layer, at: 0)
                followers.append(follower)
            }
        }
    }

    /// A soft glow around the figure and its props in a contrasting color, so it shows on any wallpaper;
    /// nil = none.
    var halo: CGColor? {
        didSet { withoutActions { Self.applyHalo(halo, to: layer) } }
    }

    static func applyHalo(_ color: CGColor?, to layer: CALayer) {
        layer.shadowColor = color
        layer.shadowOpacity = color == nil ? 0 : 0.9
        layer.shadowRadius = 1.5
        layer.shadowOffset = .zero
    }

    init(skeleton: Skeleton = .standard) {
        self.skeleton = skeleton
        build()
        withoutActions { apply(pose) }
    }

    private func build() {
        let s = skeleton
        func bone(_ name: Bone, in parent: CALayer, at point: CGPoint, line: CGFloat?, back: Bool = false) -> CALayer {
            let joint = CALayer()
            joint.bounds = .zero
            joint.position = point
            if let line {
                let shape = CAShapeLayer()
                let path = CGMutablePath()
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: 0, y: line))
                shape.path = path
                style(shape, back: back)
                joint.addSublayer(shape)
            }
            parent.addSublayer(joint)
            bones[name] = joint
            return joint
        }
        let hips = bone(.hips, in: layer, at: CGPoint(x: 0, y: s.legLength), line: nil)
        let thighBack = bone(.thighBack, in: hips, at: .zero, line: -s.thigh, back: true)
        _ = bone(.shinBack, in: thighBack, at: CGPoint(x: 0, y: -s.thigh), line: -s.shin, back: true)
        let torso = bone(.torso, in: hips, at: .zero, line: s.torso)
        let armBack = bone(.upperArmBack, in: torso, at: CGPoint(x: 0, y: s.torso), line: -s.upperArm, back: true)
        _ = bone(.forearmBack, in: armBack, at: CGPoint(x: 0, y: -s.upperArm), line: -s.forearm, back: true)
        let head = bone(.head, in: torso, at: CGPoint(x: 0, y: s.torso), line: nil)
        let circle = CAShapeLayer()
        let r = s.headRadius
        circle.path = CGPath(ellipseIn: CGRect(x: -r, y: 0, width: 2 * r, height: 2 * r), transform: nil)
        style(circle, back: false)
        head.addSublayer(circle)
        let armFront = bone(.upperArmFront, in: torso, at: CGPoint(x: 0, y: s.torso), line: -s.upperArm)
        _ = bone(.forearmFront, in: armFront, at: CGPoint(x: 0, y: -s.upperArm), line: -s.forearm)
        let thighFront = bone(.thighFront, in: hips, at: .zero, line: -s.thigh)
        _ = bone(.shinFront, in: thighFront, at: CGPoint(x: 0, y: -s.thigh), line: -s.shin)
    }

    /// Draws `shape` like the figure, in its color from now on (props too); `filled` fills it as well.
    func style(_ shape: CAShapeLayer, back: Bool = false, filled: Bool = false) {
        shape.strokeColor = color
        shape.fillColor = filled ? color : nil
        shape.lineWidth = skeleton.lineWidth
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.opacity = back ? Self.backOpacity : 1
        shapes.append(shape)
    }

    /// The rotation (counterclockwise radians) of a bone's layer in `pose`.
    static func rotation(_ bone: Bone, _ p: Pose) -> CGFloat {
        switch bone {
        case .hips: -p.body
        case .torso: -p.lean
        case .head: -p.neck
        case .upperArmBack: p.shoulderBack
        case .forearmBack: p.elbowBack
        case .upperArmFront: p.shoulderFront
        case .forearmFront: p.elbowFront
        case .thighBack: p.hipBack
        case .shinBack: p.kneeBack
        case .thighFront: p.hipFront
        case .shinFront: p.kneeFront
        }
    }

    func hipsPosition(_ p: Pose) -> CGPoint { CGPoint(x: p.hipX, y: skeleton.legLength + p.hipY) }

    /// Sets the pose at once, stopping any move.
    func apply(_ p: Pose) {
        stop()
        withoutActions { setModel(p) }
        for follower in followers { follower.apply(p) }
    }

    private func setModel(_ p: Pose) {
        pose = p
        for (bone, joint) in bones {
            joint.setValue(Self.rotation(bone, p), forKeyPath: "transform.rotation.z")
        }
        bones[.hips]?.position = hipsPosition(p)
    }

    /// Still frames a second moves are cut into: a hand-drawn look, and less work for the render server.
    /// 12 normally, 6 in Low Power Mode.
    var frameRate: Double = 12 {
        didSet { for follower in followers { follower.frameRate = frameRate } }
    }

    /// Plays `keyframes`, evenly spaced over `duration` seconds and eased between each pair. For a loop
    /// (`repeats`), end with the first pose again. The move is cut into `frameRate` still frames a
    /// second, unless `smooth` (slow moves such as breathing, where steps would show). It starts after
    /// `delay` seconds, holding its first pose until then. Followers copy it, each a moment later.
    /// The figure keeps the last pose afterwards, or the first one when a loop is stopped.
    func animate(
        _ keyframes: [Pose], duration: CFTimeInterval, repeats: Bool = false, smooth: Bool = false,
        delay: CFTimeInterval = 0
    ) {
        guard let first = keyframes.first, let last = keyframes.last else { return }
        stop()
        withoutActions { setModel(repeats ? first : last) }
        for (i, follower) in followers.enumerated() {
            follower.animate(
                keyframes, duration: duration, repeats: repeats, smooth: smooth,
                delay: delay + Self.followerDelay * Double(i + 1))
        }
        let begin = delay > 0 ? layer.convertTime(CACurrentMediaTime(), from: nil) + delay : 0
        let fps: Double? = smooth ? nil : frameRate
        let frames: [Pose]
        let keyTimes: [NSNumber]
        if let fps {
            let n = max(1, Int((duration * fps).rounded()))
            frames = (0..<n).map { Pose.sample(keyframes, at: CGFloat($0) / CGFloat(n)) } + (repeats ? [] : [last])
            // Discrete keyframes take one more key time than values.
            keyTimes = (0...n).map { NSNumber(value: Double($0) / Double(n)) } + (repeats ? [] : [1])
        } else {
            frames = keyframes
            keyTimes = keyframes.indices.map { NSNumber(value: Double($0) / Double(max(1, keyframes.count - 1))) }
        }
        func keyframe(_ keyPath: String, _ values: [Any]) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: keyPath)
            a.values = values
            a.keyTimes = keyTimes
            a.duration = duration
            a.repeatCount = repeats ? .infinity : 1
            if begin > 0 {
                a.beginTime = begin
                a.fillMode = .backwards
            }
            if fps != nil {
                a.calculationMode = .discrete
            } else {
                a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: max(1, frames.count - 1))
            }
            return a
        }
        for (bone, joint) in bones {
            joint.add(keyframe("transform.rotation.z", frames.map { Self.rotation(bone, $0) }), forKey: Self.moveKey)
        }
        bones[.hips]?.add(keyframe("position", frames.map { NSValue(point: hipsPosition($0)) }), forKey: Self.moveKey + ".position")
    }

    /// Stops the current move and any travel, and cancels callbacks waiting on them (`after`); the figure
    /// holds the model pose where it is on screen.
    func stop() {
        generation += 1
        for joint in bones.values {
            joint.removeAnimation(forKey: Self.moveKey)
            joint.removeAnimation(forKey: Self.moveKey + ".position")
        }
        if layer.animation(forKey: Self.travelKey) != nil {
            let x = presentedX
            withoutActions { layer.position.x = x }
            layer.removeAnimation(forKey: Self.travelKey)
        }
        for follower in followers { follower.stop() }
    }

    /// Counts `stop` calls, so a callback can tell that its move was replaced.
    private(set) var generation = 0
    static let travelKey = "travel"

    /// Where the figure is along the strip right now (mid-walk too).
    var presentedX: CGFloat { (layer.presentation() ?? layer).position.x }

    /// Runs `block` after `seconds`, unless the figure was stopped (or given another move) in between.
    func after(_ seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                block()
            }
        }
    }

    /// Moves the figure along the strip to `x` at `speed` points a second, then runs `done` (unless stopped).
    func travel(to x: CGFloat, speed: CGFloat, done: @escaping @MainActor () -> Void) {
        let from = presentedX
        let duration = CFTimeInterval(abs(x - from) / max(speed, 1))
        let token = generation
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                done()
            }
        }
        let a = CABasicAnimation(keyPath: "position.x")
        a.fromValue = from
        a.toValue = x
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .linear)
        withoutActions { layer.position.x = x }
        layer.add(a, forKey: Self.travelKey)
        CATransaction.commit()
    }

    /// Whether a move is playing.
    var isAnimating: Bool { bones[.torso]?.animation(forKey: Self.moveKey) != nil }

    /// The pose on screen right now (mid-move too), so the next move can start from it.
    func presentedPose() -> Pose {
        func angle(_ bone: Bone) -> CGFloat {
            guard let joint = bones[bone] else { return 0 }
            return ((joint.presentation() ?? joint).value(forKeyPath: "transform.rotation.z") as? CGFloat) ?? 0
        }
        let hips = (bones[.hips]?.presentation() ?? bones[.hips])?.position ?? hipsPosition(pose)
        return Pose(
            hipY: hips.y - skeleton.legLength, hipX: hips.x, body: -angle(.hips), lean: -angle(.torso),
            neck: -angle(.head), shoulderBack: angle(.upperArmBack), elbowBack: angle(.forearmBack),
            shoulderFront: angle(.upperArmFront), elbowFront: angle(.forearmFront), hipBack: angle(.thighBack),
            kneeBack: angle(.shinBack), hipFront: angle(.thighFront), kneeFront: angle(.shinFront))
    }

    func withoutActions(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }
}
