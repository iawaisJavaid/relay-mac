import XCTest
@testable import RelayCore

final class ViewerLifecycleTests: XCTestCase {
    func testRecognizesClientAudioFailureWithoutTreatingAllDemuxerErrorsAsAudio() {
        let failure = """
        INFO: Renderer: metal
        ERROR: Could not open audio device: CoreAudio error (AudioQueueStart): 1937010544
        ERROR: Demuxer error
        """
        XCTAssertTrue(ViewerLifecycle.hasAudioPlaybackFailure(in: failure))
        XCTAssertTrue(ViewerLifecycle.hasAudioPlaybackFailure(in: "ERROR: Could not resume audio device: Device disconnected"))
        XCTAssertTrue(ViewerLifecycle.hasAudioPlaybackFailure(in: "ERROR: Could not initialize SDL audio: No available audio device"))
        XCTAssertFalse(ViewerLifecycle.hasAudioPlaybackFailure(in: "ERROR: Demuxer error"))
        XCTAssertFalse(ViewerLifecycle.hasAudioPlaybackFailure(in: "[server] ERROR: Could not open audio device: capture failed"))
    }

    func testOpenedViewerNeverProducesStartupWarningEvenAfterOneMinute() {
        var lifecycle = ViewerLifecycle(instanceID: "current")
        XCTAssertTrue(lifecycle.viewerOpened(instanceID: "current"))
        XCTAssertFalse(lifecycle.noteSlowStart(elapsed: 65))
        XCTAssertFalse(lifecycle.noteSlowStart(elapsed: 600))
        XCTAssertEqual(lifecycle.phase, .running)
        XCTAssertNil(lifecycle.startupHint)
    }

    func testRendererMessageSplitBetweenPipeReadsIsRecognized() {
        var lifecycle = ViewerLifecycle()
        XCTAssertFalse(lifecycle.receiveLog("INFO: Ren"))
        XCTAssertTrue(lifecycle.receiveLog("derer: metal\n"))
        XCTAssertEqual(lifecycle.phase, .running)
        XCTAssertFalse(lifecycle.noteSlowStart(elapsed: 65))
    }

    func testTextureMessageAlsoRecognizesReadiness() {
        var lifecycle = ViewerLifecycle()
        XCTAssertTrue(lifecycle.receiveLog("INFO: Texture: 864x1920\n"))
        XCTAssertEqual(lifecycle.phase, .running)
    }

    func testLateSignalFromPreviousViewerCannotMarkReplacementAsReady() {
        var lifecycle = ViewerLifecycle(instanceID: "replacement")
        XCTAssertFalse(lifecycle.viewerOpened(instanceID: "previous"))
        XCTAssertEqual(lifecycle.phase, .starting)
        XCTAssertTrue(lifecycle.viewerOpened(instanceID: "replacement"))
    }

    func testLateLogsAndSignalsCannotReviveStoppingViewer() {
        var lifecycle = ViewerLifecycle(instanceID: "current")
        lifecycle.stop()
        XCTAssertFalse(lifecycle.receiveLog("Renderer: metal\nTexture: 864x1920\n"))
        XCTAssertFalse(lifecycle.viewerOpened(instanceID: "current"))
        XCTAssertFalse(lifecycle.noteSlowStart(elapsed: 65))
        XCTAssertEqual(lifecycle.phase, .stopping)
    }

    func testSlowStartProducesOnlyOnePassiveHint() {
        var lifecycle = ViewerLifecycle()
        XCTAssertFalse(lifecycle.noteSlowStart(elapsed: 24))
        XCTAssertTrue(lifecycle.noteSlowStart(elapsed: 25))
        XCTAssertNotNil(lifecycle.startupHint)
        XCTAssertEqual(lifecycle.phase, .starting)
        XCTAssertFalse(lifecycle.noteSlowStart(elapsed: 65))
    }

    func testDelayedReadinessClearsPassiveHint() {
        var lifecycle = ViewerLifecycle(instanceID: "current")
        lifecycle.noteSlowStart(elapsed: 25)
        XCTAssertTrue(lifecycle.viewerOpened(instanceID: "current"))
        XCTAssertNil(lifecycle.startupHint)
        XCTAssertEqual(lifecycle.phase, .running)
    }

    func testFinishedViewerCannotEmitAnotherStartupHintOrBecomeReady() {
        var lifecycle = ViewerLifecycle(instanceID: "current")
        lifecycle.finish()
        XCTAssertFalse(lifecycle.noteSlowStart(elapsed: 65))
        XCTAssertFalse(lifecycle.viewerOpened(instanceID: "current"))
        XCTAssertFalse(lifecycle.receiveLog("Texture: 864x1920"))
        XCTAssertEqual(lifecycle.phase, .ended)
    }
}
