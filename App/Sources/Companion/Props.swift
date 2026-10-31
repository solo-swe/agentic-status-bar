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
            case .bubble: self.layer.addSublayer(layer)
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
        }
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
