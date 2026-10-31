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

    func testFacingLeftFlipsTheFigure() {
        let figure = StickFigure()
        figure.facing = .left
        XCTAssertEqual(figure.layer.transform.m11, -1)
        figure.facing = .right
        XCTAssertEqual(figure.layer.transform.m11, 1)
    }
}
