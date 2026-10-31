import QuartzCore

/// Things the figure uses, drawn in its color and shown only while in use
/// (doc/design/desktop-companion.md › Animations).
enum Prop: Hashable {
    /// A barbell seen from the side: a weight plate in the hands.
    case barbell
    /// A pull-up bar on two posts around the figure, seen from the front.
    case pullUpBar
    /// A speech bubble by the head (`say`).
    case bubble
    /// *z*s rising from the sleeping head.
    case zzz
}

/// Where things go in the companion's strip: the bed at the end toward the middle of the screen (its
/// headboard at the outer end), and the stretch left over for walking and workouts.
struct StripLayout: Equatable {
    static let bedWidth: CGFloat = 46
    /// The mattress's top, as high as a shin, so the feet reach the floor when sitting on it.
    static let mattressHeight: CGFloat = Skeleton.standard.shin
    static let edgeMargin: CGFloat = 4
    /// Room left between the bed and a walk or workout (a pull-up bar's half width and a bit).
    static let clearance: CGFloat = 22

    var width: CGFloat
    /// The bed is at the strip's left end (the strip is in a right corner), else at its right end.
    var bedOnLeft: Bool

    init(width: CGFloat, position: String) {
        self.width = width
        bedOnLeft = position.hasSuffix("right")
    }

    /// The bed's left edge.
    var bedX: CGFloat { bedOnLeft ? Self.edgeMargin : width - Self.edgeMargin - Self.bedWidth }
    /// The way the figure faces lying in bed so its head is on the pillow (facing right, its head points left).
    var bedFacing: StickFigure.Facing { bedOnLeft ? .right : .left }
    /// Where the figure's hips are when it sits on or lies in the bed.
    var restX: CGFloat {
        let fromHeadboard: CGFloat = 26
        return bedOnLeft ? bedX + fromHeadboard : bedX + Self.bedWidth - fromHeadboard
    }
    /// Where the figure may walk or work out.
    var walkRange: ClosedRange<CGFloat> {
        bedOnLeft
            ? (bedX + Self.bedWidth + Self.clearance)...(width - Self.clearance)
            : Self.clearance...(bedX - Self.clearance)
    }
}

extension StickFigure {
    /// Shows `prop` (once; showing it again does nothing).
    func show(_ prop: Prop) {
        guard props[prop] == nil else { return }
        let layer = makeLayer(prop)
        withoutActions {
            switch prop {
            case .barbell: bones[.forearmFront]?.addSublayer(layer)
            // Behind the figure, standing on the floor around it.
            case .pullUpBar: self.layer.insertSublayer(layer, at: 0)
            case .bubble, .zzz: self.layer.addSublayer(layer)
            }
        }
        props[prop] = layer
    }

    func hide(_ prop: Prop) {
        withoutActions { props[prop]?.removeFromSuperlayer() }
        props[prop] = nil
    }

    func hideProps() {
        for prop in Array(props.keys) { hide(prop) }
    }

    private func makeLayer(_ prop: Prop) -> CALayer {
        switch prop {
        case .barbell:
            // At the hand: the tip of the front forearm.
            let r: CGFloat = 3
            let plate = CAShapeLayer()
            plate.path = CGPath(ellipseIn: CGRect(x: -r, y: -skeleton.forearm - r, width: 2 * r, height: 2 * r), transform: nil)
            style(plate, filled: true)
            return plate
        case .pullUpBar:
            let (h, w) = (Moves.barHeight, Moves.barHalfWidth)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -w, y: 0))
            path.addLine(to: CGPoint(x: -w, y: h))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: w, y: 0))
            let bar = CAShapeLayer()
            bar.path = path
            style(bar)
            bar.lineWidth = skeleton.lineWidth * 0.75
            return bar
        case .bubble:
            return makeBubble()
        case .zzz:
            return makeZzz()
        }
    }

    /// The bed, drawn in the figure's color with its headboard on the left; place it with its bottom-left
    /// corner at `StripLayout.bedX` on the floor (mirrored when the bed is at the right end).
    func makeBed(_ layout: StripLayout) -> CALayer {
        let (w, h) = (StripLayout.bedWidth, StripLayout.mattressHeight)
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: w, height: h + 8)
        container.anchorPoint = CGPoint(x: 0.5, y: 0)
        container.position = CGPoint(x: layout.bedX + w / 2, y: 0)
        if !layout.bedOnLeft { container.transform = CATransform3DMakeScale(-1, 1, 1) }
        let frame = CGMutablePath()
        // Headboard, mattress, foot.
        frame.move(to: CGPoint(x: 1, y: 0))
        frame.addLine(to: CGPoint(x: 1, y: h + 7))
        frame.move(to: CGPoint(x: 1, y: h))
        frame.addLine(to: CGPoint(x: w - 1, y: h))
        frame.addLine(to: CGPoint(x: w - 1, y: 0))
        frame.move(to: CGPoint(x: 1, y: h - 3))
        frame.addLine(to: CGPoint(x: w - 1, y: h - 3))
        let shape = CAShapeLayer()
        shape.path = frame
        style(shape)
        shape.lineWidth = skeleton.lineWidth * 0.75
        let pillow = CAShapeLayer()
        pillow.path = CGPath(roundedRect: CGRect(x: 3, y: h + 0.5, width: 8, height: 3.5), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
        style(pillow)
        pillow.lineWidth = skeleton.lineWidth * 0.75
        container.addSublayer(shape)
        container.addSublayer(pillow)
        return container
    }

    /// The area the *z*s rise through, from above the sleeping head.
    static let zzzSize = CGSize(width: 34, height: 32)

    /// Three *z*s rising and fading from above the head of a figure lying down, one after another.
    private func makeZzz() -> CALayer {
        // From just above the head, up and away from the headboard, growing as they rise.
        let container = CALayer()
        container.bounds = CGRect(origin: .zero, size: Self.zzzSize)
        container.anchorPoint = .zero
        let head = skeleton.points(Moves.lying(skeleton)).head
        container.position = CGPoint(x: head.x - 2, y: head.y + skeleton.headRadius)
        for i in 0..<3 {
            let z = CATextLayer()
            // Each letter reads the right way round when the figure faces left; `facing` keeps this up.
            z.transform = layer.transform
            z.string = "z"
            z.fontSize = CGFloat(10 + 3 * i)
            z.font = "Helvetica-Bold" as CFString
            z.alignmentMode = .center
            z.foregroundColor = color
            z.contentsScale = 2
            z.frame = CGRect(x: 0, y: 0, width: 18, height: 18)
            z.opacity = 0
            let rise = CABasicAnimation(keyPath: "position")
            rise.fromValue = NSValue(point: CGPoint(x: 6, y: 6))
            rise.toValue = NSValue(point: CGPoint(x: Self.zzzSize.width - 9, y: Self.zzzSize.height - 9))
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.2, 0.7, 1]
            let group = CAAnimationGroup()
            group.animations = [rise, fade]
            group.duration = Moves.zzzCycle
            group.repeatCount = .infinity
            // One after another.
            group.beginTime = CACurrentMediaTime() + Moves.zzzCycle * Double(i) / 3
            group.fillMode = .backwards
            z.add(group, forKey: "zzz")
            container.addSublayer(z)
        }
        return container
    }

    /// The speech bubble's size, and where its bottom-left corner sits: up and to the front of the head.
    static let bubbleSize = CGSize(width: 12, height: 11)
    var bubbleOrigin: CGPoint { CGPoint(x: 4, y: skeleton.height + 1) }

    /// Shows a bubble saying `glyph` in a `color` fill (replacing any bubble already shown).
    func say(_ glyph: String, color: CGColor) {
        hide(.bubble)
        show(.bubble)
        guard let bubble = props[.bubble] else { return }
        withoutActions {
            (bubble.sublayers?.first as? CAShapeLayer)?.fillColor = color
            (bubble.sublayers?.last as? CATextLayer)?.string = glyph
        }
    }

    /// The text in the bubble, if one is shown.
    var bubbleText: String? { (props[.bubble]?.sublayers?.last as? CATextLayer)?.string as? String }

    private func makeBubble() -> CALayer {
        let size = Self.bubbleSize
        let container = CALayer()
        container.bounds = CGRect(origin: .zero, size: size)
        container.position = CGPoint(x: bubbleOrigin.x + size.width / 2, y: bubbleOrigin.y + size.height / 2)
        // Reads the right way round when the figure faces left (it is flipped); `facing` keeps this up.
        container.transform = layer.transform
        let shape = CAShapeLayer()
        let body = CGRect(x: 0, y: 2.5, width: size.width, height: size.height - 2.5)
        let path = CGMutablePath()
        path.addRoundedRect(in: body, cornerWidth: 3, cornerHeight: 3)
        // The tail, down toward the head.
        path.move(to: CGPoint(x: 2, y: 3))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 5, y: 3))
        path.closeSubpath()
        shape.path = path
        shape.frame = container.bounds
        let text = CATextLayer()
        text.frame = body.offsetBy(dx: 0, dy: -1)
        text.alignmentMode = .center
        text.fontSize = 9
        text.font = "Helvetica-Bold" as CFString
        text.foregroundColor = CGColor(gray: 1, alpha: 1)
        text.contentsScale = 2
        container.addSublayer(shape)
        container.addSublayer(text)
        return container
    }
}
