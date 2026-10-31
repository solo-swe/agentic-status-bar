import QuartzCore

/// Things the figure uses, drawn in its color and shown only while in use
/// (doc/design/desktop-companion.md › Animations).
enum Prop: Hashable {
    /// A barbell seen from the side: a weight plate in the hands.
    case barbell
    /// A pull-up bar on two posts around the figure, seen from the front.
    case pullUpBar
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
        }
    }
}
