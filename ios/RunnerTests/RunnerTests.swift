import AVFoundation
import CallKit
import XCTest

@testable import Runner

final class CallIdentityTests: XCTestCase {
  func testUuidDiffersForAnotherRoomOrCall() {
    let uuid = CallIdentity.uuid(roomId: "!room:example.org", callId: "call-1")
    XCTAssertNotEqual(uuid, CallIdentity.uuid(roomId: "!other:example.org", callId: "call-1"))
    XCTAssertNotEqual(uuid, CallIdentity.uuid(roomId: "!room:example.org", callId: "call-2"))
    XCTAssertNotEqual(uuid, CallIdentity.uuid(roomId: "!room:example.org", callId: ""))
  }

  func testUuidDiffersWhenRoomAndCallSwapPlacesOrTheSeparatorMoves() {
    XCTAssertNotEqual(
      CallIdentity.uuid(roomId: "!room:example.org", callId: "call-1"),
      CallIdentity.uuid(roomId: "call-1", callId: "!room:example.org"))
    XCTAssertNotEqual(
      CallIdentity.uuid(roomId: "ab", callId: "c"), CallIdentity.uuid(roomId: "a", callId: "bc"))
    XCTAssertNotEqual(
      CallIdentity.uuid(roomId: "!room:example.org", callId: "1"),
      CallIdentity.uuid(roomId: "!room:example.org1", callId: ""))
  }

  func testUuidsForManyCallsInOneRoomAreDistinct() {
    let uuids = (0..<500).map {
      CallIdentity.uuid(roomId: "!room:example.org", callId: "call-\($0)")
    }
    XCTAssertEqual(Set(uuids).count, 500)
  }

  func testUuidAlwaysCarriesVersionFiveAndTheRfc4122Variant() {
    for index in 0..<256 {
      let bytes = CallIdentity.uuid(roomId: "!room-\(index):example.org", callId: "call-\(index)")
        .uuid
      XCTAssertEqual(bytes.6 >> 4, 5, "version of call \(index)")
      XCTAssertEqual(bytes.8 >> 6, 0b10, "variant of call \(index)")
    }
  }

  func testKeyJoinsRoomAndCallWithANewline() {
    XCTAssertEqual(
      CallIdentity.key(roomId: "!room:example.org", callId: "call-1"), "!room:example.org\ncall-1")
  }

  func testKeyKeepsAnEmptyCallId() {
    XCTAssertEqual(CallIdentity.key(roomId: "!room:example.org", callId: ""), "!room:example.org\n")
  }

  func testKeyDiffersWhenRoomAndCallSwapPlacesOrTheSeparatorMoves() {
    XCTAssertNotEqual(
      CallIdentity.key(roomId: "a", callId: "b"), CallIdentity.key(roomId: "b", callId: "a"))
    XCTAssertNotEqual(
      CallIdentity.key(roomId: "ab", callId: "c"), CallIdentity.key(roomId: "a", callId: "bc"))
  }

  func testEndedReasonMapsEveryWireName() {
    let expected: [(String, CXCallEndedReason)] = [
      ("remoteEnded", .remoteEnded),
      ("unanswered", .unanswered),
      ("answeredElsewhere", .answeredElsewhere),
      ("declinedElsewhere", .declinedElsewhere),
      ("failed", .failed),
    ]
    for (name, reason) in expected {
      XCTAssertEqual(CallIdentity.endedReason(name), reason, name)
    }
  }

  func testEndedReasonTreatsAMissingOrUnknownNameAsRemoteEnded() {
    XCTAssertEqual(CallIdentity.endedReason(nil), .remoteEnded)
    for name in [
      "", "timedOut", "dismissed", "callerCancelled", "declined", "Failed", "UNANSWERED", " failed",
    ] {
      XCTAssertEqual(CallIdentity.endedReason(name), .remoteEnded, name)
    }
  }
}

final class CallAudioRoutingTests: XCTestCase {
  func testRouteNamesMatchTheDartCallAudioRouteNames() {
    XCTAssertEqual(
      CallAudioRoute.allCases.map(\.rawValue), ["earpiece", "speaker", "wiredHeadset", "bluetooth"])
  }

  func testTheReceiverOutputIsTheEarpiece() {
    XCTAssertEqual(CallAudioRouting.route(forOutput: .builtInReceiver), .earpiece)
  }

  func testTheBuiltInSpeakerOutputIsTheSpeaker() {
    XCTAssertEqual(CallAudioRouting.route(forOutput: .builtInSpeaker), .speaker)
  }

  func testBluetoothAndCarOutputsAreBluetooth() {
    let ports: [AVAudioSession.Port] = [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE, .carAudio]
    for port in ports {
      XCTAssertEqual(CallAudioRouting.route(forOutput: port), .bluetooth, port.rawValue)
    }
  }

  func testHeadphoneUsbAndLineOutputsAreTheWiredHeadset() {
    let ports: [AVAudioSession.Port] = [.headphones, .usbAudio, .lineOut]
    for port in ports {
      XCTAssertEqual(CallAudioRouting.route(forOutput: port), .wiredHeadset, port.rawValue)
    }
  }

  func testAirPlayAndOtherOutputsCountAsTheSpeaker() {
    let ports: [AVAudioSession.Port] = [
      .airPlay, .HDMI, .virtual, AVAudioSession.Port(rawValue: "SomeFuturePort"),
    ]
    for port in ports {
      XCTAssertEqual(CallAudioRouting.route(forOutput: port), .speaker, port.rawValue)
    }
  }

  func testBluetoothAndCarPortsAreBluetoothHeadsets() {
    let ports: [AVAudioSession.Port] = [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE, .carAudio]
    for port in ports {
      XCTAssertEqual(CallAudioRouting.headset(for: port), .bluetooth, port.rawValue)
    }
  }

  func testHeadphoneHeadsetMicUsbAndLinePortsAreWiredHeadsets() {
    let ports: [AVAudioSession.Port] = [.headphones, .headsetMic, .usbAudio, .lineOut]
    for port in ports {
      XCTAssertEqual(CallAudioRouting.headset(for: port), .wiredHeadset, port.rawValue)
    }
  }

  func testBuiltInAndOtherPortsAreNotHeadsets() {
    let ports: [AVAudioSession.Port] = [
      .builtInMic, .builtInReceiver, .builtInSpeaker, .airPlay, .HDMI, .lineIn,
    ]
    for port in ports {
      XCTAssertNil(CallAudioRouting.headset(for: port), port.rawValue)
    }
  }

  func testBluetoothRouteUsesTheHandsFreeLowEnergyOrCarMicrophone() {
    XCTAssertEqual(
      CallAudioRouting.inputPorts(for: .bluetooth), [.bluetoothHFP, .bluetoothLE, .carAudio])
  }

  func testWiredHeadsetRouteUsesTheHeadsetMicThenUsb() {
    XCTAssertEqual(CallAudioRouting.inputPorts(for: .wiredHeadset), [.headsetMic, .usbAudio])
  }

  func testEarpieceAndSpeakerRoutesUseTheBuiltInMic() {
    XCTAssertEqual(CallAudioRouting.inputPorts(for: .earpiece), [.builtInMic])
    XCTAssertEqual(CallAudioRouting.inputPorts(for: .speaker), [.builtInMic])
  }

  func testEveryHeadsetInputPortIsRecognizedAsThatHeadset() {
    for route in [CallAudioRoute.bluetooth, .wiredHeadset] {
      for port in CallAudioRouting.inputPorts(for: route) {
        XCTAssertEqual(CallAudioRouting.headset(for: port), route, port.rawValue)
      }
    }
  }

  func testStateWithNoOutputsDefaultsToTheEarpiece() {
    XCTAssertEqual(
      CallAudioRouting.state(outputs: [], inputs: []),
      CallAudioState(route: .earpiece, headsets: []))
  }

  func testStateWithNoOutputsStillListsHeadsetInputs() {
    XCTAssertEqual(
      CallAudioRouting.state(outputs: [], inputs: [.builtInMic, .bluetoothHFP]),
      CallAudioState(route: .earpiece, headsets: [.bluetooth]))
  }

  func testStateOnTheEarpieceWithOnlyBuiltInPortsHasNoHeadsets() {
    XCTAssertEqual(
      CallAudioRouting.state(outputs: [.builtInReceiver], inputs: [.builtInMic]),
      CallAudioState(route: .earpiece, headsets: []))
  }

  func testStateOnTheSpeakerStillListsAConnectedHeadset() {
    XCTAssertEqual(
      CallAudioRouting.state(outputs: [.builtInSpeaker], inputs: [.builtInMic, .bluetoothHFP]),
      CallAudioState(route: .speaker, headsets: [.bluetooth]))
  }

  func testStateCombinesHeadsetsFromOutputsAndInputs() {
    XCTAssertEqual(
      CallAudioRouting.state(outputs: [.bluetoothA2DP], inputs: [.builtInMic, .headsetMic]),
      CallAudioState(route: .bluetooth, headsets: [.bluetooth, .wiredHeadset]))
  }

  func testStateTakesTheRouteFromTheFirstOutput() {
    XCTAssertEqual(
      CallAudioRouting.state(outputs: [.headphones, .builtInSpeaker], inputs: []),
      CallAudioState(route: .wiredHeadset, headsets: [.wiredHeadset]))
  }

  func testArgumentsCarryOnlyTheRouteAndHeadsets() {
    let arguments = CallAudioState(route: .wiredHeadset, headsets: [.wiredHeadset]).arguments
    XCTAssertEqual(Set(arguments.keys), ["route", "headsets"])
    XCTAssertEqual(arguments["route"] as? String, "wiredHeadset")
    XCTAssertEqual(arguments["headsets"] as? [String], ["wiredHeadset"])
  }

  func testArgumentsListHeadsetsInRouteOrder() {
    let reversed = CallAudioState(route: .speaker, headsets: [.bluetooth, .wiredHeadset])
    XCTAssertEqual(reversed.arguments["headsets"] as? [String], ["wiredHeadset", "bluetooth"])
    let every = CallAudioState(route: .speaker, headsets: Set(CallAudioRoute.allCases.reversed()))
    XCTAssertEqual(
      every.arguments["headsets"] as? [String],
      ["earpiece", "speaker", "wiredHeadset", "bluetooth"])
  }

  func testArgumentsWithNoHeadsetsSendAnEmptyList() {
    let arguments = CallAudioState(route: .earpiece, headsets: []).arguments
    XCTAssertEqual(arguments["route"] as? String, "earpiece")
    XCTAssertEqual(arguments["headsets"] as? [String], [])
  }

  func testTheCallConfigurationIsPlayAndRecordVoiceChatWithBluetooth() {
    XCTAssertTrue(
      CallAudioRouting.isCallConfiguration(
        category: .playAndRecord, mode: .voiceChat,
        options: [.allowBluetoothHFP, .allowBluetoothA2DP]
      ))
  }

  func testTheCallConfigurationAcceptsExtraOptions() {
    let extras: [AVAudioSession.CategoryOptions] = [
      .allowAirPlay, .overrideMutedMicrophoneInterruption,
    ]
    for extra in extras {
      XCTAssertTrue(
        CallAudioRouting.isCallConfiguration(
          category: .playAndRecord, mode: .voiceChat,
          options: [.allowBluetoothHFP, .allowBluetoothA2DP, extra]), "\(extra.rawValue)")
    }
  }

  func testTheCallConfigurationRejectsOptionsThatChangeHowTheCallSounds() {
    let foreign: [AVAudioSession.CategoryOptions] = [
      .mixWithOthers, .duckOthers, .interruptSpokenAudioAndMixWithOthers,
    ]
    for option in foreign {
      XCTAssertFalse(
        CallAudioRouting.isCallConfiguration(
          category: .playAndRecord, mode: .voiceChat,
          options: [.allowBluetoothHFP, .allowBluetoothA2DP, option]), "\(option.rawValue)")
    }
  }

  func testASpeakerFirstCallDefaultsToTheSpeakerAndAnotherDoesNot() {
    XCTAssertTrue(CallAudioRouting.callOptions(speakerFirst: true).contains(.defaultToSpeaker))
    XCTAssertFalse(CallAudioRouting.callOptions(speakerFirst: false).contains(.defaultToSpeaker))
    XCTAssertTrue(
      CallAudioRouting.callOptions(speakerFirst: true).isSuperset(of: CallAudioRouting.callOptions))
  }

  func testBothCallConfigurationsAreTheCalls() {
    for speakerFirst in [true, false] {
      XCTAssertTrue(
        CallAudioRouting.isCallConfiguration(
          category: .playAndRecord, mode: .voiceChat,
          options: CallAudioRouting.callOptions(speakerFirst: speakerFirst)), "\(speakerFirst)")
    }
  }

  func testTheCallConfigurationTellsWhetherItStartsOnTheSpeaker() {
    let speakerFirst = CallAudioRouting.callOptions(speakerFirst: true)
    let plain = CallAudioRouting.callOptions(speakerFirst: false)
    XCTAssertTrue(
      CallAudioRouting.isCallConfiguration(
        category: .playAndRecord, mode: .voiceChat, options: speakerFirst, speakerFirst: true))
    XCTAssertFalse(
      CallAudioRouting.isCallConfiguration(
        category: .playAndRecord, mode: .voiceChat, options: speakerFirst, speakerFirst: false))
    XCTAssertFalse(
      CallAudioRouting.isCallConfiguration(
        category: .playAndRecord, mode: .voiceChat, options: plain, speakerFirst: true))
  }

  func testAVoiceMessageSessionOnTheSpeakerIsNotTheCall() {
    XCTAssertFalse(
      CallAudioRouting.isCallConfiguration(
        category: .playAndRecord, mode: .default,
        options: CallAudioRouting.callOptions(speakerFirst: true)))
  }

  func testTheCallConfigurationRequiresBluetoothA2DP() {
    XCTAssertFalse(
      CallAudioRouting.isCallConfiguration(
        category: .playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP]))
  }

  func testTheCallConfigurationRequiresTheVoiceChatMode() {
    for mode: AVAudioSession.Mode in [.videoChat, .default, .voicePrompt] {
      XCTAssertFalse(
        CallAudioRouting.isCallConfiguration(
          category: .playAndRecord, mode: mode, options: [.allowBluetoothHFP, .allowBluetoothA2DP]),
        mode.rawValue)
    }
  }

  func testTheCallConfigurationRequiresPlayAndRecord() {
    for category: AVAudioSession.Category in [.playback, .record, .soloAmbient] {
      XCTAssertFalse(
        CallAudioRouting.isCallConfiguration(
          category: category, mode: .voiceChat, options: [.allowBluetoothHFP, .allowBluetoothA2DP]),
        category.rawValue)
    }
  }

  func testAChosenRouteIsTheStartingRoute() {
    XCTAssertEqual(
      CallAudioRouting.startingRoute(wanted: .earpiece, isVideo: true, headsets: []), .earpiece)
    XCTAssertEqual(
      CallAudioRouting.startingRoute(wanted: .speaker, isVideo: false, headsets: [.bluetooth]),
      .speaker)
  }

  func testAVideoCallWithoutAHeadsetStartsOnTheSpeaker() {
    XCTAssertEqual(
      CallAudioRouting.startingRoute(wanted: nil, isVideo: true, headsets: []), .speaker)
  }

  func testAVideoCallWithAHeadsetKeepsTheSystemRoute() {
    XCTAssertNil(
      CallAudioRouting.startingRoute(wanted: nil, isVideo: true, headsets: [.wiredHeadset]))
    XCTAssertNil(CallAudioRouting.startingRoute(wanted: nil, isVideo: true, headsets: [.bluetooth]))
  }

  func testARestoredRouteIsTheLastOneReported() {
    XCTAssertEqual(
      CallAudioRouting.restoredRoute(
        reported: .earpiece, wanted: .speaker, isVideo: true, headsets: []),
      .earpiece)
    XCTAssertEqual(
      CallAudioRouting.restoredRoute(
        reported: .bluetooth, wanted: nil, isVideo: false, headsets: [.bluetooth]),
      .bluetooth)
  }

  func testWithNothingReportedTheStartingRouteIsRestored() {
    XCTAssertEqual(
      CallAudioRouting.restoredRoute(reported: nil, wanted: nil, isVideo: true, headsets: []),
      .speaker)
    XCTAssertEqual(
      CallAudioRouting.restoredRoute(
        reported: nil, wanted: .wiredHeadset, isVideo: false, headsets: [.wiredHeadset]),
      .wiredHeadset)
    XCTAssertNil(
      CallAudioRouting.restoredRoute(reported: nil, wanted: nil, isVideo: false, headsets: []))
  }

  func testAVoiceCallKeepsTheSystemRoute() {
    XCTAssertNil(CallAudioRouting.startingRoute(wanted: nil, isVideo: false, headsets: []))
    XCTAssertNil(
      CallAudioRouting.startingRoute(wanted: nil, isVideo: false, headsets: [.bluetooth]))
  }

  func testTheSpeakerLeavesTheInputUnchanged() {
    XCTAssertEqual(
      CallAudioRouting.preferredInput(for: .speaker, available: [.builtInMic, .bluetoothHFP]),
      .unchanged)
    XCTAssertEqual(CallAudioRouting.preferredInput(for: .speaker, available: []), .unchanged)
  }

  func testTheEarpieceWithAHeadsetConnectedPrefersTheBuiltInMic() {
    XCTAssertEqual(
      CallAudioRouting.preferredInput(for: .earpiece, available: [.bluetoothHFP, .builtInMic]),
      .prefer(.builtInMic))
    XCTAssertEqual(
      CallAudioRouting.preferredInput(for: .earpiece, available: [.builtInMic, .headsetMic]),
      .prefer(.builtInMic))
  }

  func testTheEarpieceWithoutAHeadsetClearsThePreferredInput() {
    XCTAssertEqual(
      CallAudioRouting.preferredInput(for: .earpiece, available: [.builtInMic]), .clear)
    XCTAssertEqual(CallAudioRouting.preferredInput(for: .earpiece, available: []), .clear)
  }

  func testTheEarpieceWithAHeadsetButNoBuiltInMicClearsThePreferredInput() {
    XCTAssertEqual(
      CallAudioRouting.preferredInput(for: .earpiece, available: [.headsetMic]), .clear)
  }

  func testAHeadsetRoutePrefersTheFirstMatchingInputInTheSystemOrder() {
    XCTAssertEqual(
      CallAudioRouting.preferredInput(
        for: .bluetooth, available: [.builtInMic, .carAudio, .bluetoothHFP]),
      .prefer(.carAudio))
    XCTAssertEqual(
      CallAudioRouting.preferredInput(for: .wiredHeadset, available: [.usbAudio, .headsetMic]),
      .prefer(.usbAudio))
  }

  func testAHeadsetRouteWithoutAMatchingInputLeavesTheInputUnchanged() {
    XCTAssertEqual(
      CallAudioRouting.preferredInput(for: .bluetooth, available: [.builtInMic, .headsetMic]),
      .unchanged)
    XCTAssertEqual(
      CallAudioRouting.preferredInput(for: .wiredHeadset, available: [.builtInMic, .bluetoothHFP]),
      .unchanged)
  }
}

final class CallToneSourceTests: XCTestCase {
  private let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!

  private func toneFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tone-\(UUID()).caf")
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 800))
    buffer.frameLength = 800
    for frame in 0..<800 {
      buffer.floatChannelData![0][frame] = 0.5
    }
    try file.write(from: buffer)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func offlineEngine() throws -> AVAudioEngine {
    let engine = AVAudioEngine()
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 256)
    return engine
  }

  private func loudest(_ engine: AVAudioEngine) throws -> Float {
    try engine.start()
    defer { engine.stop() }
    let out = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 256))
    _ = try engine.renderOffline(256, to: out)
    return (0..<Int(out.frameLength)).map { abs(out.floatChannelData![0][$0]) }.max() ?? 0
  }

  private func joined(_ source: CallToneSource) throws -> AVAudioEngine {
    let engine = try offlineEngine()
    source.join(engine, mixer: engine.mainMixerNode)
    return engine
  }

  func testTheToneIsSilentUntilItPlays() throws {
    let source = try XCTUnwrap(CallToneSource(contentsOf: toneFile()))
    XCTAssertEqual(try loudest(joined(source)), 0)
  }

  func testAPlayingToneSoundsThroughTheEngine() throws {
    let source = try XCTUnwrap(CallToneSource(contentsOf: toneFile()))
    source.setPlaying(true)
    XCTAssertGreaterThan(try loudest(joined(source)), 0.1)
  }

  func testAStoppedToneFallsSilent() throws {
    let source = try XCTUnwrap(CallToneSource(contentsOf: toneFile()))
    source.setPlaying(true)
    source.setPlaying(false)
    XCTAssertEqual(try loudest(joined(source)), 0)
  }

  func testJoiningTheSameEngineAgainConnectsTheToneOnce() throws {
    let source = try XCTUnwrap(CallToneSource(contentsOf: toneFile()))
    let engine = try joined(source)
    source.join(engine, mixer: engine.mainMixerNode)
    XCTAssertEqual(engine.outputConnectionPoints(for: source.node, outputBus: 0).count, 1)
  }

  func testANewEngineTakesTheToneOver() throws {
    let source = try XCTUnwrap(CallToneSource(contentsOf: toneFile()))
    _ = try joined(source)
    let next = try joined(source)
    source.setPlaying(true)
    XCTAssertTrue(source.node.engine === next)
    XCTAssertGreaterThan(try loudest(next), 0.1)
  }

  func testLeavingAReleasedEngineFreesTheTone() throws {
    let source = try XCTUnwrap(CallToneSource(contentsOf: toneFile()))
    let engine = try joined(source)
    source.leave(engine)
    XCTAssertNil(source.node.engine)
  }

  func testLeavingAnotherEngineKeepsTheTone() throws {
    let source = try XCTUnwrap(CallToneSource(contentsOf: toneFile()))
    let engine = try joined(source)
    source.leave(AVAudioEngine())
    XCTAssertTrue(source.node.engine === engine)
  }

  func testAMissingFileGivesNoTone() {
    XCTAssertNil(CallToneSource(contentsOf: URL(fileURLWithPath: "/nonexistent/ringback.wav")))
  }
}

final class OnceCompletionTests: XCTestCase {
  func testTheHandlerRunsOnceWithTheFirstValue() {
    let calls = Recorder<Int>()
    let completion = OnceCompletion<Int> { calls.add($0) }
    completion(1)
    completion(2)
    XCTAssertEqual(calls.values, [1])
  }

  func testItIsDoneOnlyAfterTheFirstCall() {
    let completion = OnceCompletion<Void> { _ in }
    XCTAssertFalse(completion.isDone)
    completion(())
    XCTAssertTrue(completion.isDone)
  }

  func testCallsRacingOnManyThreadsRunTheHandlerOnce() {
    let calls = Recorder<Int>()
    let completion = OnceCompletion<Int> { calls.add($0) }
    DispatchQueue.concurrentPerform(iterations: 200) { completion($0) }
    XCTAssertEqual(calls.values.count, 1)
  }
}

@MainActor
final class WakeLockLedgerTests: XCTestCase {
  func testAcquireBeginsANamedTaskAndHoldsItUntilTheTimeout() {
    let harness = WakeLockHarness()
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    XCTAssertEqual(harness.tasks.events, ["begin zuno:message_action #1"])
    XCTAssertEqual(harness.ledger.heldTags, ["message_action"])
    XCTAssertEqual(harness.timers.pendingDelays, [30_000])
  }

  func testAcquiringTheSameTagAgainReplacesTheEarlierTask() {
    let harness = WakeLockHarness()
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    harness.ledger.acquire("message_action", timeoutMs: 20_000)
    XCTAssertEqual(
      harness.tasks.events,
      ["begin zuno:message_action #1", "end #1", "begin zuno:message_action #2"])
    XCTAssertEqual(harness.tasks.running, [2])
    XCTAssertEqual(harness.timers.pendingDelays, [20_000])
  }

  func testReleaseEndsTheTaskAndCancelsItsTimeout() {
    let harness = WakeLockHarness()
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    harness.ledger.release("message_action")
    XCTAssertEqual(harness.tasks.events, ["begin zuno:message_action #1", "end #1"])
    XCTAssertTrue(harness.ledger.heldTags.isEmpty)
    XCTAssertTrue(harness.timers.pendingDelays.isEmpty)
  }

  func testTheTimeoutEndsTheTask() {
    let harness = WakeLockHarness()
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    harness.timers.fire(0)
    XCTAssertEqual(harness.tasks.running, [])
    XCTAssertTrue(harness.ledger.heldTags.isEmpty)
  }

  func testAStaleTimeoutLeavesTheTaskThatReplacedItRunning() {
    let harness = WakeLockHarness()
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    harness.timers.fire(0, evenIfCancelled: true)
    XCTAssertEqual(harness.tasks.running, [2])
    XCTAssertEqual(harness.ledger.heldTags, ["message_action"])
  }

  func testTheSystemExpiringTheTaskEndsIt() {
    let harness = WakeLockHarness()
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    harness.tasks.expire(1)
    XCTAssertEqual(harness.tasks.events, ["begin zuno:message_action #1", "end #1"])
    XCTAssertTrue(harness.ledger.heldTags.isEmpty)
    XCTAssertTrue(harness.timers.pendingDelays.isEmpty)
  }

  func testAStaleExpirationLeavesTheTaskThatReplacedItRunning() {
    let harness = WakeLockHarness()
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    harness.tasks.expire(1)
    XCTAssertEqual(harness.tasks.running, [2])
    XCTAssertEqual(harness.tasks.events.filter { $0.hasPrefix("end") }, ["end #1"])
  }

  func testLocksWithDifferentTagsAreIndependent() {
    let harness = WakeLockHarness()
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    harness.ledger.acquire("call_decline", timeoutMs: 30_000)
    harness.ledger.release("message_action")
    XCTAssertEqual(harness.ledger.heldTags, ["call_decline"])
    XCTAssertEqual(harness.tasks.running, [2])
  }

  func testATaskTheSystemRefusesHoldsNothing() {
    let harness = WakeLockHarness()
    harness.tasks.refuses = true
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    harness.ledger.release("message_action")
    XCTAssertTrue(harness.ledger.heldTags.isEmpty)
    XCTAssertTrue(harness.timers.pendingDelays.isEmpty)
    XCTAssertTrue(harness.tasks.events.isEmpty)
  }

  func testReleasingATagThatIsNotHeldDoesNothing() {
    let harness = WakeLockHarness()
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    harness.ledger.release("call_decline")
    XCTAssertEqual(harness.tasks.running, [1])
  }

  func testANegativeTimeoutCountsAsZero() {
    let harness = WakeLockHarness()
    harness.ledger.acquire("message_action", timeoutMs: -5)
    XCTAssertEqual(harness.timers.pendingDelays, [0])
  }
}

@MainActor
final class MainActorTimerTests: XCTestCase {
  func testAScheduledTimerFiresAfterItsDelay() {
    let fired = expectation(description: "fired")
    _ = MainActorTimer.schedule(10) { fired.fulfill() }
    wait(for: [fired], timeout: 2)
  }

  func testACancelledTimerNeverFires() {
    let fired = expectation(description: "fired")
    fired.isInverted = true
    let cancel = MainActorTimer.schedule(10) { fired.fulfill() }
    cancel()
    wait(for: [fired], timeout: 0.3)
  }

  func testAnAbsurdDelayIsCappedInsteadOfOverflowing() {
    let fired = expectation(description: "fired")
    fired.isInverted = true
    let cancel = MainActorTimer.schedule(Int.max) { fired.fulfill() }
    wait(for: [fired], timeout: 0.1)
    cancel()
  }
}

final class LaunchHandoffTests: XCTestCase {
  func testARoomOpenedBeforeAnyEngineWaitsForTheLaunch() {
    var state = LaunchHandoff<String>()
    XCTAssertFalse(state.offer("!r:x"))
    let engine = state.attach()
    XCTAssertEqual(state.take(engine), "!r:x")
    XCTAssertNil(state.pending)
  }

  func testTheLatestRoomWinsWhileNobodyListens() {
    var state = LaunchHandoff<String>()
    let engine = state.attach()
    XCTAssertFalse(state.offer("!a:x"))
    XCTAssertFalse(state.offer("!b:x"))
    XCTAssertEqual(state.take(engine), "!b:x")
  }

  func testOnceTheAppTookTheLaunchRoomOpensAreDelivered() {
    var state = LaunchHandoff<String>()
    let engine = state.attach()
    XCTAssertNil(state.take(engine))
    XCTAssertTrue(state.offer("!r:x"))
    XCTAssertNil(state.pending)
  }

  func testTheLaunchRoomIsHandedOutOnce() {
    var state = LaunchHandoff<String>()
    let engine = state.attach()
    _ = state.offer("!r:x")
    XCTAssertEqual(state.take(engine), "!r:x")
    XCTAssertNil(state.take(engine))
  }

  func testANewEngineTakesTheLaunchBeforeRoomsAreDelivered() {
    var state = LaunchHandoff<String>()
    let first = state.attach()
    _ = state.take(first)
    let second = state.attach()
    XCTAssertFalse(state.offer("!r:x"))
    XCTAssertEqual(state.take(second), "!r:x")
    XCTAssertTrue(state.offer("!s:x"))
  }

  func testAnOlderEngineCannotTakeThePendingRoom() {
    var state = LaunchHandoff<String>()
    let first = state.attach()
    let second = state.attach()
    _ = state.offer("!r:x")
    XCTAssertNil(state.take(first))
    XCTAssertEqual(state.pending, "!r:x")
    XCTAssertFalse(state.offer("!r:x"))
    XCTAssertEqual(state.take(second), "!r:x")
  }

  func testRoomsOpenedAfterTheListeningEngineDetachedWait() {
    var state = LaunchHandoff<String>()
    let engine = state.attach()
    _ = state.take(engine)
    state.detach(engine)
    XCTAssertFalse(state.offer("!r:x"))
    XCTAssertEqual(state.pending, "!r:x")
  }

  func testAnOlderEngineDetachingKeepsTheNewListener() {
    var state = LaunchHandoff<String>()
    let first = state.attach()
    let second = state.attach()
    _ = state.take(second)
    state.detach(first)
    XCTAssertTrue(state.offer("!r:x"))
  }
}

@MainActor
final class ClientLeaseLedgerTests: XCTestCase {
  func testAFreeLeaseIsGrantedAtOnce() {
    let harness = LeaseHarness()
    XCTAssertEqual(harness.acquire(1, .app).calls, ["t1"])
    XCTAssertEqual(harness.ledger.holders, [1: .app])
    XCTAssertTrue(harness.timers.pendingDelays.isEmpty)
  }

  func testAnEngineThatHoldsTheLeaseIsGrantedAgainWhateverTheKind() {
    let harness = LeaseHarness()
    _ = harness.acquire(1, .background)
    XCTAssertEqual(harness.acquire(1, .app).calls, ["t2"])
    XCTAssertEqual(harness.acquire(1, .background).calls, ["t3"])
    XCTAssertEqual(harness.ledger.holders, [1: .app])
    XCTAssertTrue(harness.yields.isEmpty)
  }

  func testAnEngineHoldingAnyAppTokenCountsAsAnAppHolder() {
    let harness = LeaseHarness()
    _ = harness.acquire(1, .app)
    for _ in 0..<19 {
      _ = harness.acquire(1, .background)
    }
    XCTAssertEqual(harness.ledger.holders, [1: .app])
    XCTAssertEqual(harness.acquire(2, .background).calls, [nil])
    XCTAssertTrue(harness.yields.isEmpty)
  }

  func testABackgroundRequestIsRefusedAtOnceWhileAnotherEngineHoldsAnAppLease() {
    let harness = LeaseHarness()
    _ = harness.acquire(1, .app)
    XCTAssertEqual(harness.acquire(2, .background).calls, [nil])
    XCTAssertTrue(harness.yields.isEmpty)
    XCTAssertTrue(harness.ledger.waitingEngines.isEmpty)
    XCTAssertTrue(harness.timers.pendingDelays.isEmpty)
  }

  func testAnAppRequestWaitsForAnotherAppHolderAndGetsTheLeaseOnRelease() {
    let harness = LeaseHarness()
    _ = harness.acquire(1, .app)
    let waiting = harness.acquire(2, .app, waitMs: 5_000)
    XCTAssertTrue(waiting.calls.isEmpty)
    XCTAssertTrue(harness.yields.isEmpty)
    XCTAssertEqual(harness.timers.pendingDelays, [5_000])
    harness.ledger.release(token: "t1")
    XCTAssertEqual(waiting.calls, ["t2"])
    XCTAssertEqual(harness.ledger.holders, [2: .app])
    XCTAssertTrue(harness.timers.pendingDelays.isEmpty)
  }

  func testAnAppRequestIsForceGrantedWhenAnotherAppHolderKeepsTheLease() {
    let harness = LeaseHarness()
    _ = harness.acquire(1, .app)
    let waiting = harness.acquire(2, .app, waitMs: 5_000)
    harness.timers.fire(0)
    XCTAssertEqual(waiting.calls, ["t2"])
    XCTAssertEqual(harness.ledger.holders, [1: .app, 2: .app])
    XCTAssertEqual(harness.logs.count, 1)
  }

  func testAnAppRequestAsksABackgroundHolderToYieldAndGetsTheLeaseOnRelease() {
    let harness = LeaseHarness()
    _ = harness.acquire(2, .background)
    let app = harness.acquire(1, .app)
    XCTAssertEqual(harness.yields, [2])
    XCTAssertTrue(app.calls.isEmpty)
    harness.ledger.release(token: "t1")
    XCTAssertEqual(app.calls, ["t2"])
    XCTAssertEqual(harness.ledger.holders, [1: .app])
    XCTAssertTrue(harness.logs.isEmpty)
  }

  func testAnAppRequestIsForceGrantedAndLoggedWhenABackgroundHolderDoesNotYield() {
    let harness = LeaseHarness()
    _ = harness.acquire(2, .background)
    let app = harness.acquire(1, .app, waitMs: 3_000)
    XCTAssertEqual(harness.timers.pendingDelays, [3_000])
    harness.timers.fire(0)
    XCTAssertEqual(app.calls, ["t2"])
    XCTAssertEqual(harness.ledger.holders, [1: .app, 2: .background])
    XCTAssertEqual(
      harness.logs, ["force-granted an app lease to engine 1 while engines [2] held it"])
  }

  func testABackgroundRequestQueuesBehindABackgroundHolderAndAsksItToYield() {
    let harness = LeaseHarness()
    _ = harness.acquire(2, .background)
    let waiting = harness.acquire(3, .background)
    XCTAssertEqual(harness.yields, [2])
    XCTAssertTrue(waiting.calls.isEmpty)
    harness.ledger.release(token: "t1")
    XCTAssertEqual(waiting.calls, ["t2"])
    XCTAssertEqual(harness.ledger.holders, [3: .background])
  }

  func testABackgroundRequestGetsNothingWhenItsWaitRunsOut() {
    let harness = LeaseHarness()
    _ = harness.acquire(2, .background)
    let waiting = harness.acquire(3, .background, waitMs: 2_000)
    harness.timers.fire(0)
    XCTAssertEqual(waiting.calls, [nil])
    XCTAssertEqual(harness.ledger.holders, [2: .background])
    XCTAssertTrue(harness.ledger.waitingEngines.isEmpty)
    XCTAssertTrue(harness.logs.isEmpty)
  }

  func testBackgroundWaitersAreServedInTheOrderTheyAsked() {
    let harness = LeaseHarness()
    _ = harness.acquire(2, .background)
    let first = harness.acquire(3, .background)
    let second = harness.acquire(4, .background)
    XCTAssertEqual(harness.ledger.waitingEngines, [3, 4])
    harness.ledger.release(token: "t1")
    XCTAssertEqual(first.calls, ["t2"])
    XCTAssertTrue(second.calls.isEmpty)
    XCTAssertEqual(harness.yields, [2, 3])
    harness.ledger.release(token: "t2")
    XCTAssertEqual(second.calls, ["t3"])
  }

  func testAppWaitersGoAheadOfBackgroundWaitersWhoAreThenRefused() {
    let harness = LeaseHarness()
    _ = harness.acquire(2, .background)
    let background = harness.acquire(3, .background)
    let app = harness.acquire(1, .app)
    XCTAssertEqual(harness.ledger.waitingEngines, [1, 3])
    harness.ledger.release(token: "t1")
    XCTAssertEqual(app.calls, ["t2"])
    XCTAssertEqual(background.calls, [nil])
    XCTAssertTrue(harness.timers.pendingDelays.isEmpty)
  }

  func testAppWaitersAreServedInTheOrderTheyAsked() {
    let harness = LeaseHarness()
    _ = harness.acquire(1, .app)
    let first = harness.acquire(2, .app)
    let second = harness.acquire(3, .app)
    harness.ledger.release(token: "t1")
    XCTAssertEqual(first.calls, ["t2"])
    XCTAssertTrue(second.calls.isEmpty)
    harness.ledger.release(token: "t2")
    XCTAssertEqual(second.calls, ["t3"])
  }

  func testAnEngineHoldsTheLeaseUntilItsLastTokenIsReleased() {
    let harness = LeaseHarness()
    _ = harness.acquire(2, .background)
    _ = harness.acquire(2, .background)
    let app = harness.acquire(1, .app)
    harness.ledger.release(token: "t1")
    XCTAssertTrue(app.calls.isEmpty)
    harness.ledger.release(token: "t2")
    XCTAssertEqual(app.calls, ["t3"])
  }

  func testADetachedEngineLosesItsLeasesAndItsWaitersGetNothing() {
    let harness = LeaseHarness()
    _ = harness.acquire(2, .background)
    let app = harness.acquire(1, .app)
    let leaving = harness.acquire(3, .background)
    harness.ledger.detach(engine: 3)
    XCTAssertEqual(leaving.calls, [nil])
    XCTAssertTrue(app.calls.isEmpty)
    XCTAssertEqual(harness.timers.pendingDelays.count, 1)
    harness.ledger.detach(engine: 2)
    XCTAssertEqual(app.calls, ["t2"])
    XCTAssertEqual(harness.ledger.holders, [1: .app])
    XCTAssertTrue(harness.timers.pendingDelays.isEmpty)
  }

  func testReleasingAnUnknownTokenChangesNothing() {
    let harness = LeaseHarness()
    _ = harness.acquire(1, .app)
    let waiting = harness.acquire(2, .app)
    harness.ledger.release(token: "unknown")
    harness.ledger.release(token: "t1")
    harness.ledger.release(token: "t1")
    XCTAssertEqual(waiting.calls, ["t2"])
    XCTAssertEqual(harness.ledger.holders, [2: .app])
  }

  func testAForceGrantedAppLeaseRefusesTheBackgroundWaiters() {
    let harness = LeaseHarness()
    _ = harness.acquire(2, .background)
    let background = harness.acquire(3, .background, waitMs: 9_000)
    let app = harness.acquire(1, .app, waitMs: 5_000)
    harness.timers.fire(1)
    XCTAssertEqual(app.calls, ["t2"])
    XCTAssertEqual(background.calls, [nil])
    XCTAssertTrue(harness.timers.pendingDelays.isEmpty)
  }

  func testAWaiterIsAnsweredOnceEvenIfItsTimerFiresAfterItWasServed() {
    let harness = LeaseHarness()
    _ = harness.acquire(1, .app)
    let waiting = harness.acquire(2, .app)
    harness.ledger.release(token: "t1")
    harness.timers.fire(0, evenIfCancelled: true)
    XCTAssertEqual(waiting.calls, ["t2"])
    XCTAssertEqual(harness.ledger.holders, [2: .app])
    XCTAssertTrue(harness.logs.isEmpty)
  }

  func testAHolderIsAskedToYieldOncePerHoldAndAgainWhenItHoldsAgain() {
    let harness = LeaseHarness()
    _ = harness.acquire(2, .background)
    _ = harness.acquire(3, .background)
    _ = harness.acquire(4, .background)
    XCTAssertEqual(harness.yields, [2])
    harness.ledger.release(token: "t1")
    harness.ledger.release(token: "t2")
    XCTAssertEqual(harness.yields, [2, 3])
    _ = harness.acquire(2, .background)
    XCTAssertEqual(harness.yields, [2, 3, 4])
    harness.ledger.release(token: "t3")
    _ = harness.acquire(3, .background)
    XCTAssertEqual(harness.yields, [2, 3, 4, 2])
  }

  func testAnAppHolderIsNeverAskedToYield() {
    let harness = LeaseHarness()
    _ = harness.acquire(1, .app)
    _ = harness.acquire(2, .app)
    _ = harness.acquire(3, .background)
    XCTAssertTrue(harness.yields.isEmpty)
  }

  func testANegativeWaitCountsAsZero() {
    let harness = LeaseHarness()
    _ = harness.acquire(1, .app)
    _ = harness.acquire(2, .app, waitMs: -1)
    XCTAssertEqual(harness.timers.pendingDelays, [0])
  }
}

@MainActor
private final class WakeLockHarness {
  let tasks = FakeBackgroundTasks()
  let timers = FakeTimers()
  private(set) lazy var ledger = WakeLockLedger(
    begin: { [tasks] in tasks.begin($0, $1) },
    end: { [tasks] in tasks.end($0) },
    schedule: { [timers] in timers.schedule($0, $1) })
}

@MainActor
private final class LeaseReply {
  private(set) var calls: [String?] = []

  func record(_ token: String?) {
    calls.append(token)
  }
}

@MainActor
private final class LeaseHarness {
  let timers = FakeTimers()
  private(set) var yields: [Int] = []
  private(set) var logs: [String] = []
  private var tokens = 0
  private(set) lazy var ledger = ClientLeaseLedger(
    makeToken: { [unowned self] in
      tokens += 1
      return "t\(tokens)"
    },
    schedule: { [timers] in timers.schedule($0, $1) },
    sendYield: { [unowned self] in yields.append($0) },
    log: { [unowned self] in logs.append($0) })

  func acquire(_ engine: Int, _ kind: ClientLeaseKind, waitMs: Int = 5_000) -> LeaseReply {
    let reply = LeaseReply()
    ledger.acquire(engine: engine, kind: kind, waitMs: waitMs) { reply.record($0) }
    return reply
  }
}

final class AppDataWipeTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("app-data-wipe-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
    try super.tearDownWithError()
  }

  private func make(_ path: String) throws -> URL {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: url)
    return url
  }

  private func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
  }

  func testEverythingGoesButTheOpenDatabaseItsSidecarsAndTheSystemsFiles() throws {
    for path in [
      "support/zuno.db", "support/zuno.db-wal", "support/zuno.db-shm", "support/zuno.db-journal",
      "support/zuno.db.bak", "support/other.db", "support/media/photo.jpg",
      "support/com.apple.state", "documents/export.txt", "inbox/share.json",
    ] {
      _ = try make(path)
    }
    let keptPath = root.appendingPathComponent("support/media/../zuno.db").path

    let wiped = AppDataPlugin.empty(
      required: [root.appendingPathComponent("support"), root.appendingPathComponent("documents")],
      optional: [root.appendingPathComponent("inbox")], keeping: [keptPath])

    XCTAssertTrue(wiped)
    for path in [
      "support/zuno.db", "support/zuno.db-wal", "support/zuno.db-shm", "support/zuno.db-journal",
      "support/com.apple.state",
    ] {
      XCTAssertTrue(exists(path), path)
    }
    for path in [
      "support/zuno.db.bak", "support/other.db", "support/media", "documents/export.txt",
      "inbox/share.json",
    ] {
      XCTAssertFalse(exists(path), path)
    }
  }

  func testAMissingDirectoryIsAlreadyEmpty() {
    XCTAssertTrue(
      AppDataPlugin.empty(
        required: [root.appendingPathComponent("absent"), nil], optional: [], keeping: ["/x"]))
  }

  func testAnUnreadableRequiredDirectoryFailsTheWipeButAnOptionalOneDoesNot() throws {
    let file = try make("plain-file")

    XCTAssertTrue(AppDataPlugin.empty(required: [], optional: [file], keeping: ["/x"]))
    XCTAssertFalse(AppDataPlugin.empty(required: [file], optional: [], keeping: ["/x"]))
  }

  @MainActor
  func testTheWipeSignsThePushSessionOutBeforeEmptyingTheFilesAndFailsWithEither() async {
    for (signedOut, emptied, wiped) in [
      (true, true, true), (false, true, false), (true, false, false),
    ] {
      let steps = Recorder<String>()
      let plugin = AppDataPlugin(
        signOut: {
          steps.add("sign out")
          return signedOut
        },
        emptyFiles: { keep in
          steps.add("empty \(keep)")
          return emptied
        })

      let reply = await channelReply(from: plugin, method: "wipe", arguments: ["keep": ["/db"]])

      XCTAssertEqual(reply.answer as? Bool, wiped)
      XCTAssertEqual(steps.values, ["sign out", #"empty ["/db"]"#])
    }
  }

  @MainActor
  func testWithoutTheOpenDatabaseNothingIsSignedOutOrEmptied() {
    let steps = Recorder<String>()
    let plugin = AppDataPlugin(
      signOut: {
        steps.add("sign out")
        return true
      },
      emptyFiles: { _ in
        steps.add("empty")
        return true
      })

    XCTAssertEqual(
      immediateReply(from: plugin, method: "wipe", arguments: ["keep": [String]()]) as? Bool, false)
    XCTAssertEqual(steps.values, [])
  }
}
