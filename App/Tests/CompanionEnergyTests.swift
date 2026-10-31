import AppKit
import XCTest
@testable import Agentic_Status_Bar

@MainActor
final class CompanionEnergyTests: XCTestCase {
    func testItStopsWheneverItCannotBeSeen() {
        XCTAssertTrue(CompanionEnergy().shouldAnimate)
        XCTAssertFalse(CompanionEnergy(visible: false).shouldAnimate)
        XCTAssertFalse(CompanionEnergy(displaysAsleep: true).shouldAnimate)
        XCTAssertFalse(CompanionEnergy(screenLocked: true).shouldAnimate)
        XCTAssertTrue(CompanionEnergy(lowPower: true, reduceMotion: true).shouldAnimate, "slower or still, but shown")
    }

    func testLowPowerHalvesTheFrameRateAndReduceMotionHoldsStill() {
        XCTAssertEqual(CompanionEnergy().frameRate, 12)
        XCTAssertEqual(CompanionEnergy(lowPower: true).frameRate, 6)
        XCTAssertFalse(CompanionEnergy().stillPoses)
        XCTAssertTrue(CompanionEnergy(reduceMotion: true).stillPoses)
    }

    func testTheWatcherFollowsSleepLockAndOcclusion() {
        let (center, workspace, distributed) = (NotificationCenter(), NotificationCenter(), NotificationCenter())
        let panel = CompanionWindow.makePanel()
        var reported: [CompanionEnergy] = []
        let watcher = CompanionEnergyWatcher(
            panel: panel, initial: CompanionEnergy(), center: center, workspace: workspace, distributed: distributed
        ) { reported.append($0) }

        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        XCTAssertTrue(watcher.energy.displaysAsleep)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertFalse(watcher.energy.displaysAsleep)

        distributed.post(name: CompanionEnergyWatcher.screenLocked, object: nil)
        XCTAssertTrue(watcher.energy.screenLocked)
        XCTAssertFalse(watcher.energy.shouldAnimate)
        distributed.post(name: CompanionEnergyWatcher.screenUnlocked, object: nil)
        XCTAssertTrue(watcher.energy.shouldAnimate)

        // The panel isn't on screen, so an occlusion change finds it hidden.
        center.post(name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        XCTAssertFalse(watcher.energy.visible)
        XCTAssertEqual(reported.count, 5)

        // Only changes are reported.
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertEqual(reported.count, 5)
    }

    func testLowPowerFramesAndStillZs() {
        let figure = StickFigure()
        figure.frameRate = 6
        figure.animate([.standing, Pose(lean: 0.3)], duration: 1)
        let rotation = figure.bones[.torso]?.animation(forKey: StickFigure.moveKey) as? CAKeyframeAnimation
        XCTAssertEqual(rotation?.values?.count, 7, "6 frames a second, then the last pose")
        figure.animate([.standing, Pose(lean: 0.3), .standing], duration: 4, repeats: true, smooth: true)
        let smooth = figure.bones[.torso]?.animation(forKey: StickFigure.moveKey) as? CAKeyframeAnimation
        XCTAssertNotEqual(smooth?.calculationMode, .discrete)

        figure.showStillZzz()
        let zs = figure.props[.zzz]?.sublayers ?? []
        XCTAssertEqual(zs.count, 3)
        XCTAssertTrue(zs.allSatisfy { $0.animationKeys() == nil && $0.opacity == 1 }, "no motion")
        XCTAssertLessThan(zs[0].position.y, zs[2].position.y, "rising along the path")
    }
}
