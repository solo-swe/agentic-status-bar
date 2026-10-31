import AppKit
import XCTest
@testable import Agentic_Status_Bar

@MainActor
final class StickFigureTests: XCTestCase {
    let s = Skeleton.standard

    func testStandingStandsOnTheFloorWithTheHeadOnTop() {
        let p = s.points(.standing)
        XCTAssertEqual(p.hips, CGPoint(x: 0, y: s.legLength))
        XCTAssertEqual(p.footBack.y, 0, accuracy: 0.001)
        XCTAssertEqual(p.footFront.y, 0, accuracy: 0.001)
        XCTAssertEqual(p.neck, CGPoint(x: 0, y: s.legLength + s.torso))
        XCTAssertEqual(p.head.y, s.legLength + s.torso + s.headRadius, accuracy: 0.001)
        XCTAssertEqual(s.height, p.head.y + s.headRadius, accuracy: 0.001)
        // Relaxed arms hang beside the torso, below the neck.
        XCTAssertLessThan(p.handFront.y, p.neck.y - s.upperArm)
    }

    func testAnglesFollowTheSignConventions() {
        // A positive hip swings the leg forward (+x); a negative knee bends the shin back.
        let p = s.points(Pose(hipFront: 0.5, kneeFront: -0.5))
        XCTAssertGreaterThan(p.kneeFront.x, 0)
        XCTAssertEqual(p.footFront.x, p.kneeFront.x, accuracy: 0.001)
        // Leaning forward moves the neck forward; tipping the body π/2 lays the figure face down, forward.
        XCTAssertGreaterThan(s.points(Pose(lean: 0.3)).neck.x, 0)
        let down = s.points(Pose(body: .pi / 2))
        XCTAssertEqual(down.neck.y, down.hips.y, accuracy: 0.001)
        XCTAssertEqual(down.neck.x, s.torso, accuracy: 0.001)
    }

    func testSittingPutsTheHipsOnTheSeatWithLevelThighs() {
        let p = s.points(.sitting(seatHeight: s.shin))
        XCTAssertEqual(p.hips.y, s.shin, accuracy: 0.001)
        XCTAssertEqual(p.kneeFront.y, p.hips.y, accuracy: 0.001)
        XCTAssertEqual(p.footFront.y, 0, accuracy: 0.001)
    }

    func testMirroringSwapsTheLimbs() {
        let p = Pose(shoulderBack: 1, elbowBack: 2, shoulderFront: 3, elbowFront: 4, hipBack: 5, kneeBack: 6, hipFront: 7, kneeFront: 8)
        XCTAssertEqual(p.mirrored.shoulderFront, 1)
        XCTAssertEqual(p.mirrored.kneeBack, 8)
        XCTAssertEqual(p.mirrored.mirrored, p)
    }

    func testSamplingHitsTheKeyframesAndEasesBetween() {
        let a = Pose(), b = Pose(lean: 1)
        XCTAssertEqual(Pose.sample([a, b], at: 0), a)
        XCTAssertEqual(Pose.sample([a, b], at: 1), b)
        XCTAssertEqual(Pose.sample([a, b], at: 0.5).lean, 0.5, accuracy: 0.001)
        XCTAssertLessThan(Pose.sample([a, b], at: 0.1).lean, 0.1, "eased in")
        XCTAssertEqual(Pose.sample([a, b, a], at: 0.5), b)
    }

    func testApplySetsEveryBone() {
        let figure = StickFigure()
        XCTAssertEqual(Set(figure.bones.keys), Set(StickFigure.Bone.allCases))
        let p = Pose(hipY: -3, hipX: 2, body: 0.1, lean: 0.2, neck: 0.3, shoulderBack: 0.4, elbowBack: 0.5,
                     shoulderFront: 0.6, elbowFront: 0.7, hipBack: 0.8, kneeBack: -0.9, hipFront: 1.0, kneeFront: -1.1)
        figure.apply(p)
        XCTAssertEqual(figure.pose, p)
        for bone in StickFigure.Bone.allCases {
            let angle = figure.bones[bone]?.value(forKeyPath: "transform.rotation.z") as? CGFloat
            XCTAssertEqual(angle ?? .nan, StickFigure.rotation(bone, p), accuracy: 0.0001, "\(bone)")
        }
        XCTAssertEqual(figure.bones[.hips]?.position, CGPoint(x: 2, y: s.legLength - 3))
        // Read back from the layers, the pose is the same.
        let read = figure.presentedPose()
        for field in Pose.fields { XCTAssertEqual(read[keyPath: field], p[keyPath: field], accuracy: 0.0001) }
    }

    func testAMoveAnimatesEveryJointAndEndsInItsLastPose() {
        let figure = StickFigure()
        let end = Pose(lean: 0.4)
        figure.animate([.standing, end], duration: 1)
        XCTAssertTrue(figure.isAnimating)
        for joint in figure.bones.values { XCTAssertNotNil(joint.animation(forKey: StickFigure.moveKey)) }
        XCTAssertEqual(figure.pose, end)
        let rotation = figure.bones[.torso]?.animation(forKey: StickFigure.moveKey) as? CAKeyframeAnimation
        XCTAssertEqual(rotation?.calculationMode, .discrete)
        XCTAssertEqual(rotation?.values?.count, 13, "12 frames a second, then the last pose")
        XCTAssertEqual(rotation?.keyTimes?.count, 14)
        figure.stop()
        XCTAssertFalse(figure.isAnimating)
    }

    func testALoopRepeatsAndRestsOnItsFirstPose() {
        let figure = StickFigure()
        let start = Pose(lean: 0.2)
        figure.animate([start, .standing, start], duration: 0.5, repeats: true)
        XCTAssertEqual(figure.pose, start)
        let rotation = figure.bones[.torso]?.animation(forKey: StickFigure.moveKey)
        XCTAssertEqual(rotation?.repeatCount, .infinity)
    }

    // MARK: Walk

    func testTheWalkKeepsAFootOnTheFloor() {
        let walk = Moves.walk()
        XCTAssertEqual(walk.count, 9, "8 poses, then the first again")
        XCTAssertEqual(walk.first, walk.last)
        for (i, pose) in walk.enumerated() {
            let p = s.points(pose)
            let lower = min(p.footBack.y, p.footFront.y)
            // On the floor, or up on the toes (at most a point) in the up poses.
            XCTAssertGreaterThanOrEqual(lower, -0.001, "pose \(i) doesn't sink into the floor")
            XCTAssertLessThanOrEqual(lower, 1, "pose \(i) keeps a foot down")
        }
        // At contact both feet touch the floor.
        let contact = s.points(walk[0])
        XCTAssertEqual(contact.footBack.y, contact.footFront.y, accuracy: 1.5)
        XCTAssertGreaterThan(contact.footFront.x, contact.footBack.x)
    }

    func testTheSecondStepMirrorsTheFirst() {
        let walk = Moves.walk()
        for i in 0..<4 { XCTAssertEqual(walk[i + 4], walk[i].mirrored) }
    }

    func testTravelPerCycleIsTwoStrides() {
        XCTAssertGreaterThan(Moves.stride(), 5)
        XCTAssertEqual(Moves.walkSpeed() * CGFloat(Moves.walkCycle), 2 * Moves.stride(), accuracy: 0.001)
    }

    func testWalkingTurnsTowardTheTargetAndTravels() {
        let figure = StickFigure()
        figure.layer.position.x = 100
        figure.walk(to: 40)
        XCTAssertEqual(figure.facing, .left)
        XCTAssertTrue(figure.isAnimating)
        XCTAssertNotNil(figure.layer.animation(forKey: StickFigure.travelKey))
        XCTAssertEqual(figure.layer.position.x, 40, "the model is at the target; the animation gets it there")
        figure.walk(to: 200)
        XCTAssertEqual(figure.facing, .right)
        figure.stop()
        XCTAssertNil(figure.layer.animation(forKey: StickFigure.travelKey))
        XCTAssertFalse(figure.isAnimating)
    }

    func testAStoppedWalkDoesNotReportArriving() {
        let figure = StickFigure()
        figure.layer.position.x = 0
        var arrived = false
        figure.walk(to: 100) { arrived = true }
        figure.stop()
        let moment = expectation(description: "a moment")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { moment.fulfill() }
        wait(for: [moment], timeout: 1)
        XCTAssertFalse(arrived)
    }

    func testStrollTargetsAreFarEnoughAndInRange() {
        let range: ClosedRange<CGFloat> = 20...200
        for x in stride(from: CGFloat(20), through: 200, by: 30) {
            for r in stride(from: 0.0, to: 1.0, by: 0.1) {
                let target = StickFigure.strollTarget(from: x, in: range, random: r)
                XCTAssertTrue(range.contains(target), "\(target) in range from \(x)")
                XCTAssertGreaterThanOrEqual(abs(target - x), 60 - 0.001, "from \(x) with \(r)")
            }
        }
    }

    // MARK: Workouts

    func testReachingPutsTheHandsOnTheTarget() {
        let neck = s.points(.standing).neck
        for target in [CGPoint(x: neck.x + 7, y: neck.y - 3), CGPoint(x: neck.x + 4, y: neck.y + 10), CGPoint(x: neck.x + 8, y: neck.y - 11)] {
            for behind in [true, false] {
                let p = s.points(s.reaching(.standing, hand: target, elbowsBehind: behind, backOffset: 0))
                XCTAssertEqual(p.handFront.x, target.x, accuracy: 0.01)
                XCTAssertEqual(p.handFront.y, target.y, accuracy: 0.01)
                XCTAssertEqual(p.handBack.x, target.x, accuracy: 0.01)
                // The elbow ends up on the asked side of the line from the shoulder to the hand.
                let side = (target.x - neck.x) * (p.elbowFront.y - neck.y) - (target.y - neck.y) * (p.elbowFront.x - neck.x)
                let other = s.points(s.reaching(.standing, hand: target, elbowsBehind: !behind, backOffset: 0)).elbowFront
                XCTAssertEqual(behind, p.elbowFront.x <= other.x + 0.001, "side \(side)")
            }
        }
    }

    func testPushUpsKeepHandsAndFeetPlanted() {
        let push = Moves.pushUps()
        let planks = push.loop
        let first = s.points(planks[0])
        for pose in planks {
            let p = s.points(pose)
            XCTAssertEqual(p.footBack.y, 0, accuracy: 0.01)
            XCTAssertEqual(p.footFront.x, first.footFront.x, accuracy: 0.01)
            XCTAssertEqual(p.handFront.y, 0, accuracy: 0.01)
            XCTAssertEqual(p.handFront.x, first.handFront.x, accuracy: 0.01)
            XCTAssertGreaterThan(p.head.y - s.headRadius, -0.01, "the head stays above the floor")
        }
        XCTAssertLessThan(s.points(planks[1]).neck.y, first.neck.y, "down is lower")
    }

    func testActivitiesFlowFromIntroThroughLoopToStanding() {
        for activity in [Moves.weightLifting(), Moves.pushUps(), Moves.jumpingJacks(), Moves.pullUps()] {
            XCTAssertEqual(activity.loop.first, activity.loop.last, activity.name)
            XCTAssertEqual(activity.intro.last, activity.loop.first, activity.name)
            XCTAssertEqual(activity.outro.last, .standing, activity.name)
            XCTAssertEqual(activity.duration(reps: 2), activity.introDuration + 2 * activity.rep + activity.outroDuration)
            for pose in activity.intro + activity.loop + activity.outro {
                let p = s.points(pose)
                XCTAssertGreaterThan(min(p.footBack.y, p.footFront.y), -0.01, "\(activity.name): feet not under the floor")
            }
        }
        XCTAssertEqual(Moves.weightLifting().prop, .barbell)
        XCTAssertNil(Moves.pushUps().prop)
    }

    func testJumpingJacksHopBetweenClosedAndOpen() {
        let loop = Moves.jumpingJacks().loop
        let (closed, air, open) = (s.points(loop[0]), s.points(loop[1]), s.points(loop[2]))
        XCTAssertEqual(min(closed.footBack.y, closed.footFront.y), 0, accuracy: 0.01)
        XCTAssertEqual(min(open.footBack.y, open.footFront.y), 0, accuracy: 0.01)
        XCTAssertGreaterThan(min(air.footBack.y, air.footFront.y), 2, "both feet off the floor mid-hop")
        XCTAssertGreaterThan(open.footFront.x - open.footBack.x, closed.footFront.x - closed.footBack.x + 8, "legs apart")
        XCTAssertGreaterThan(open.handFront.y, open.neck.y, "arms up")
        XCTAssertGreaterThan(open.handBack.y, open.neck.y)
    }

    func testPullUpsHoldTheBarAndFitTheStrip() {
        let pull = Moves.pullUps()
        let top = CompanionWindow.size.height - CompanionWindow.floorY
        for pose in pull.loop {
            let p = s.points(pose)
            XCTAssertEqual(p.handFront.y, Moves.barHeight, accuracy: 0.01)
            XCTAssertEqual(p.handBack.y, Moves.barHeight, accuracy: 0.01)
            XCTAssertGreaterThan(p.handFront.x, 0)
            XCTAssertLessThan(p.handBack.x, 0)
            // Elbows out: right of the line from the neck up to the front hand, left of the one to the back hand.
            func side(_ hand: CGPoint, _ elbow: CGPoint) -> CGFloat {
                (hand.x - p.neck.x) * (elbow.y - p.neck.y) - (hand.y - p.neck.y) * (elbow.x - p.neck.x)
            }
            XCTAssertLessThan(side(p.handFront, p.elbowFront), 0, "front elbow out")
            XCTAssertGreaterThan(side(p.handBack, p.elbowBack), 0, "back elbow out")
            XCTAssertLessThanOrEqual(p.head.y + s.headRadius, top, "the head stays in the strip")
        }
        XCTAssertGreaterThanOrEqual(s.points(pull.loop[1]).neck.y, Moves.barHeight, "the chin over the bar")
        XCTAssertLessThan(Moves.barHeight, top)
        XCTAssertEqual(pull.prop, .pullUpBar)
    }

    func testTheBarStandsBehindTheFigureWhileShown() {
        let figure = StickFigure()
        figure.show(.pullUpBar)
        XCTAssertTrue(figure.layer.sublayers?.first === figure.props[.pullUpBar])
        figure.hide(.pullUpBar)
        XCTAssertFalse(figure.layer.sublayers?.contains { $0 is CAShapeLayer } ?? false)
    }

    // MARK: Wave

    func testTheWaveRaisesSwingsLowersAndWaits() {
        let wave = Moves.wave()
        XCTAssertEqual(wave.first, wave.last)
        let raised = wave.filter { $0.shoulderFront > 2 }
        XCTAssertEqual(raised.count, 8, "raised, three swings out and in, raised")
        let neck = s.points(wave[0]).neck
        XCTAssertTrue(raised.allSatisfy { s.points($0).handFront.y > neck.y }, "the hand up by the head")
        let rests = wave.filter { $0 == wave[0] }.count
        XCTAssertGreaterThanOrEqual(Double(rests - 1) * Moves.waveStep, 2, "about 2 s of waiting")
        // The swings move the hand side to side.
        let swingXs = wave[3...8].map { s.points($0).handFront.x }
        XCTAssertGreaterThan((swingXs.max() ?? 0) - (swingXs.min() ?? 0), 5)
    }

    func testTheBubbleSaysWhyAndGoesAway() {
        XCTAssertEqual(Moves.bubbleGlyph(reason: "permission"), "!")
        XCTAssertEqual(Moves.bubbleGlyph(reason: "question"), "?")
        XCTAssertEqual(Moves.bubbleGlyph(reason: nil), "!")
        let figure = StickFigure()
        figure.wave("?", color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(figure.bubbleText, "?")
        XCTAssertTrue(figure.isAnimating)
        let shape = figure.props[.bubble]?.sublayers?.first as? CAShapeLayer
        XCTAssertEqual(shape?.fillColor, CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        figure.say("!", color: CGColor(gray: 0, alpha: 1))
        XCTAssertEqual(figure.bubbleText, "!")
        XCTAssertEqual(figure.layer.sublayers?.filter { $0 === figure.props[.bubble] }.count, 1, "one bubble")
        // The bubble stays readable when the figure turns.
        figure.facing = .left
        XCTAssertEqual(figure.props[.bubble]?.transform.m11, -1)
        figure.stop()
        figure.hideProps()
        XCTAssertNil(figure.bubbleText)
        // The bubble fits in the strip.
        XCTAssertLessThanOrEqual(figure.bubbleOrigin.y + StickFigure.bubbleSize.height, CompanionWindow.size.height - CompanionWindow.floorY)
    }

    // MARK: Bed

    func testTheBedIsAtTheInnerEndAndTheRestIsForWalking() {
        let width = CompanionWindow.size.width
        for position in ["bottom-right", "top-right", "bottom-left", "top-left"] {
            let layout = StripLayout(width: width, position: position)
            let bed = layout.bedX...(layout.bedX + StripLayout.bedWidth)
            XCTAssertEqual(layout.bedOnLeft, position.hasSuffix("right"), "toward the middle of the screen")
            XCTAssertGreaterThanOrEqual(bed.lowerBound, 0)
            XCTAssertLessThanOrEqual(bed.upperBound, width)
            XCTAssertTrue(bed.contains(layout.restX))
            XCTAssertFalse(layout.walkRange.overlaps(bed), "\(position): walks and workouts stay off the bed")
            XCTAssertGreaterThan(layout.walkRange.upperBound - layout.walkRange.lowerBound, 120)
            // A pull-up bar fits at either end of the walking range.
            XCTAssertGreaterThanOrEqual(layout.walkRange.lowerBound - Moves.barHalfWidth, 0)
            XCTAssertLessThanOrEqual(layout.walkRange.upperBound + Moves.barHalfWidth, width)
        }
        XCTAssertEqual(StripLayout(width: width, position: "bottom-right").bedFacing, .right)
        XCTAssertEqual(StripLayout(width: width, position: "bottom-left").bedFacing, .left)
    }

    func testLyingInBedHeadOnThePillow() {
        let layout = StripLayout(width: CompanionWindow.size.width, position: "bottom-right")
        let p = s.points(Moves.lying())
        let bed = layout.bedX...(layout.bedX + StripLayout.bedWidth)
        // Lying facing right, so the head is behind the hips, toward the headboard; all of it on the bed.
        for point in [p.head, p.neck, p.hips, p.kneeFront, p.footFront, p.footBack] {
            XCTAssertTrue(bed.contains(layout.restX + point.x), "\(point) on the bed")
            XCTAssertGreaterThanOrEqual(point.y, StripLayout.mattressHeight - 0.01, "\(point) on the mattress, not in it")
        }
        XCTAssertLessThan(p.head.x, p.hips.x)
        XCTAssertLessThan(p.head.y, StripLayout.mattressHeight + 8, "lying, not sitting up")
        XCTAssertEqual(Moves.breathing().first, Moves.lying())
        XCTAssertEqual(Moves.breathing().last, Moves.lying())
    }

    func testSittingOnTheBedsEdge() {
        let p = s.points(Moves.sittingOnBed())
        XCTAssertEqual(p.hips.y, StripLayout.mattressHeight, accuracy: 0.01)
        XCTAssertEqual(p.footFront.y, 0, accuracy: 0.01, "feet on the floor")
        let idle = Moves.sittingIdle()
        XCTAssertEqual(idle.first, idle.last)
        XCTAssertTrue(idle.contains { $0.neck > 0.2 }, "a tilt of the head now and then")
    }

    func testTheHaloContrastsWithTheColorAndCoversProps() {
        XCTAssertEqual(CompanionWindow.halo(for: CGColor(gray: 0.1, alpha: 1)), CGColor(gray: 1, alpha: 1))
        XCTAssertEqual(CompanionWindow.halo(for: CGColor(gray: 0.9, alpha: 1)), CGColor(gray: 0, alpha: 1))
        XCTAssertEqual(CompanionWindow.halo(for: CGColor(red: 1, green: 0.85, blue: 0, alpha: 1)), CGColor(gray: 0, alpha: 1))
        let figure = StickFigure()
        figure.halo = CGColor(gray: 1, alpha: 1)
        XCTAssertEqual(figure.layer.shadowColor, CGColor(gray: 1, alpha: 1))
        XCTAssertGreaterThan(figure.layer.shadowOpacity, 0.5)
        figure.halo = nil
        XCTAssertEqual(figure.layer.shadowOpacity, 0)
    }

    func testTheZsAreBigAndStayInTheStrip() {
        let figure = StickFigure()
        figure.show(.zzz)
        let container = figure.props[.zzz]
        let sizes = container?.sublayers?.compactMap { ($0 as? CATextLayer)?.fontSize } ?? []
        XCTAssertGreaterThanOrEqual(sizes.min() ?? 0, 10)
        let top = (container?.position.y ?? 0) + StickFigure.zzzSize.height
        XCTAssertLessThanOrEqual(top, CompanionWindow.size.height - CompanionWindow.floorY)
        figure.facing = .left
        XCTAssertTrue(container?.sublayers?.allSatisfy { $0.transform.m11 == -1 } ?? false, "letters read right")
    }

    func testTheZsRiseOnlyWhileShown() {
        let figure = StickFigure()
        figure.show(.zzz)
        let zs = figure.props[.zzz]?.sublayers?.compactMap { $0 as? CATextLayer } ?? []
        XCTAssertEqual(zs.map { $0.string as? String }, ["z", "z", "z"])
        XCTAssertTrue(zs.allSatisfy { $0.animation(forKey: "zzz") != nil })
        figure.color = CGColor(gray: 0.5, alpha: 1)
        XCTAssertTrue(zs.allSatisfy { $0.foregroundColor == CGColor(gray: 0.5, alpha: 1) })
        figure.hideProps()
        XCTAssertNil(figure.props[.zzz])
    }

    func testTheBedIsMirroredAtTheRightEnd() {
        let figure = StickFigure()
        let left = figure.makeBed(StripLayout(width: 260, position: "bottom-right"))
        let right = figure.makeBed(StripLayout(width: 260, position: "bottom-left"))
        XCTAssertEqual(left.transform.m11, 1)
        XCTAssertEqual(right.transform.m11, -1, "headboard at the outer end")
        XCTAssertEqual(right.position.x, 260 - StripLayout.edgeMargin - StripLayout.bedWidth / 2)
    }

    func testTheBarbellIsInTheHandsOnlyWhileShown() {
        let figure = StickFigure()
        figure.show(.barbell)
        figure.show(.barbell)
        XCTAssertEqual(figure.bones[.forearmFront]?.sublayers?.filter { figure.props[.barbell] === $0 }.count, 1)
        figure.hideProps()
        XCTAssertNil(figure.props[.barbell])
        XCTAssertFalse(figure.bones[.forearmFront]?.sublayers?.contains { $0 is CAShapeLayer && ($0 as? CAShapeLayer)?.fillColor != nil } ?? false)
    }

    func testFacingLeftFlipsTheFigure() {
        let figure = StickFigure()
        figure.facing = .left
        XCTAssertEqual(figure.layer.transform.m11, -1)
        figure.facing = .right
        XCTAssertEqual(figure.layer.transform.m11, 1)
    }
}
