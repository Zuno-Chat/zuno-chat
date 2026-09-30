import AVFoundation
import CallKit
import UIKit
import XCTest

@testable import Runner

final class CallIdentityTests: XCTestCase {
  func testUuidIsStableForTheSameRoomAndCall() {
    XCTAssertEqual(
      CallIdentity.uuid(roomId: "!room:example.org", callId: "call-1"),
      CallIdentity.uuid(roomId: "!room:example.org", callId: "call-1"))
  }

  func testUuidMatchesTheRfc4122NameBasedSha1UuidOfTheKey() {
    XCTAssertEqual(
      CallIdentity.uuid(roomId: "!room:example.org", callId: "call-1").uuidString,
      "F3584D12-AE55-5FE8-A44D-AC078068BB34")
    XCTAssertEqual(
      CallIdentity.uuid(roomId: "!room:example.org", callId: "").uuidString,
      "3949A790-1A82-5211-8869-6F1A41FF786C")
    XCTAssertEqual(
      CallIdentity.uuid(roomId: "!caf\u{E9}:example.org", callId: "").uuidString,
      "E4F64BDA-083F-5728-84A1-075D710AF361")
  }

  func testUuidDiffersForAnotherRoomOrCall() {
    let uuid = CallIdentity.uuid(roomId: "!room:example.org", callId: "call-1")
    XCTAssertNotEqual(uuid, CallIdentity.uuid(roomId: "!other:example.org", callId: "call-1"))
    XCTAssertNotEqual(uuid, CallIdentity.uuid(roomId: "!room:example.org", callId: "call-2"))
    XCTAssertNotEqual(uuid, CallIdentity.uuid(roomId: "!room:example.org", callId: ""))
  }

  func testUuidDiffersWhenRoomAndCallSwapPlaces() {
    XCTAssertNotEqual(
      CallIdentity.uuid(roomId: "!room:example.org", callId: "call-1"),
      CallIdentity.uuid(roomId: "call-1", callId: "!room:example.org"))
  }

  func testUuidDiffersWhenTheSeparatorMovesBetweenRoomAndCall() {
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

final class CallKitRefusalTests: XCTestCase {
  func testNoErrorMeansTheRingIsShown() {
    XCTAssertNil(CallKitCenter.refusal(nil))
  }

  func testACallCallKitAlreadyShowsCountsAsShown() {
    XCTAssertNil(CallKitCenter.refusal(CXErrorCodeIncomingCallError(.callUUIDAlreadyExists)))
  }

  func testAnUnknownOrUnentitledRefusalMeansCallKitIsUnavailable() {
    XCTAssertEqual(CallKitCenter.refusal(CXErrorCodeIncomingCallError(.unknown)), "unavailable")
    XCTAssertEqual(CallKitCenter.refusal(CXErrorCodeIncomingCallError(.unentitled)), "unavailable")
  }

  func testAnErrorOutsideTheIncomingCallDomainMeansCallKitIsUnavailable() {
    XCTAssertEqual(CallKitCenter.refusal(URLError(.timedOut)), "unavailable")
    XCTAssertEqual(
      CallKitCenter.refusal(NSError(domain: NSCocoaErrorDomain, code: 3)), "unavailable")
    XCTAssertEqual(CallKitCenter.refusal(CXError(.unentitled)), "unavailable")
    XCTAssertEqual(
      CallKitCenter.refusal(CXErrorCodeRequestTransactionError(.callUUIDAlreadyExists)),
      "unavailable")
  }

  func testEveryOtherRefusalMeansTheRingWasFiltered() {
    let codes: [CXErrorCodeIncomingCallError.Code] = [
      .filteredByDoNotDisturb, .filteredByBlockList, .filteredDuringRestrictedSharingMode,
      .callIsProtected, .filteredBySensitiveParticipants,
    ]
    for code in codes {
      XCTAssertEqual(
        CallKitCenter.refusal(CXErrorCodeIncomingCallError(code)), "filtered", "\(code.rawValue)")
    }
  }

  func testARefusalBridgedFromObjectiveCIsReadByItsCode() {
    let domain = CXErrorCodeIncomingCallError.errorDomain
    XCTAssertNil(CallKitCenter.refusal(NSError(domain: domain, code: 2)))
    XCTAssertEqual(CallKitCenter.refusal(NSError(domain: domain, code: 1)), "unavailable")
    XCTAssertEqual(CallKitCenter.refusal(NSError(domain: domain, code: 3)), "filtered")
  }
}

final class CallKitRingtoneTests: XCTestCase {
  func testTheSystemRingtonePlaysWhenTheSettingWasNeverSaved() {
    XCTAssertNil(CallKitCenter.ringtoneSound(nil))
  }

  func testTheSystemRingtonePlaysWhenTheRingtoneIsOn() {
    XCTAssertNil(CallKitCenter.ringtoneSound(true))
    XCTAssertNil(CallKitCenter.ringtoneSound(NSNumber(value: true)))
  }

  func testTheSilentRingPlaysWhenTheRingtoneIsOff() {
    XCTAssertEqual(CallKitCenter.ringtoneSound(false), "silent_ring.caf")
    XCTAssertEqual(CallKitCenter.ringtoneSound(NSNumber(value: false)), "silent_ring.caf")
  }

  func testAValueThatIsNotABoolKeepsTheSystemRingtone() {
    XCTAssertNil(CallKitCenter.ringtoneSound("false"))
    XCTAssertNil(CallKitCenter.ringtoneSound(Data()))
  }

  func testAnOffSettingReadBackFromUserDefaultsSelectsTheSilentRing() throws {
    let suite = "im.zuno.chat.tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(false, forKey: "flutter.settings.ringtone_enabled")
    XCTAssertEqual(
      CallKitCenter.ringtoneSound(defaults.object(forKey: "flutter.settings.ringtone_enabled")),
      "silent_ring.caf")
  }
}

final class CallKitSystemEndTests: XCTestCase {
  func testASystemEndInTheFirst25SecondsOfRingingIsADecline() {
    for ringing: TimeInterval in [0, 1, 24.9] {
      XCTAssertEqual(
        CallKitCenter.systemEndEvent(ringingFor: ringing, answerWithdrawn: false), "declineCall",
        "\(ringing) s")
    }
  }

  func testASystemEndAfter25SecondsOfRingingIsAMissedRing() {
    for ringing: TimeInterval in [25, 25.1, 55, 60] {
      XCTAssertEqual(
        CallKitCenter.systemEndEvent(ringingFor: ringing, answerWithdrawn: false), "ringEnded",
        "\(ringing) s")
    }
  }

  func testASystemEndOfAnAnswerTheAppNeverTookIsADecline() {
    XCTAssertEqual(
      CallKitCenter.systemEndEvent(ringingFor: nil, answerWithdrawn: true), "declineCall")
  }

  func testASystemEndOfAnOngoingCallIsAHangUp() {
    XCTAssertEqual(
      CallKitCenter.systemEndEvent(ringingFor: nil, answerWithdrawn: false), "hangUpCall")
  }
}

final class CallKitResourceTests: XCTestCase {
  func testTheAppBundleShipsTheSilentRing() throws {
    let name = try XCTUnwrap(CallKitCenter.ringtoneSound(false))
    XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: nil))
  }

  func testTheAppBundleShipsTheCallKitIcon() {
    XCTAssertNotNil(UIImage(named: "CallKitIcon")?.pngData())
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
      .defaultToSpeaker, .mixWithOthers, .duckOthers, .interruptSpokenAudioAndMixWithOthers,
    ]
    for option in foreign {
      XCTAssertFalse(
        CallAudioRouting.isCallConfiguration(
          category: .playAndRecord, mode: .voiceChat,
          options: [.allowBluetoothHFP, .allowBluetoothA2DP, option]), "\(option.rawValue)")
    }
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

final class CallRingbackToneTests: XCTestCase {
  func testHeaderDescribesSixteenBitMonoPcmAtTheDefaultRate() {
    let wav = CallRingback.ringbackTone()
    XCTAssertEqual(text(wav, at: 0), "RIFF")
    XCTAssertEqual(integer(wav, at: 4, bytes: 4), wav.count - 8, "RIFF chunk size")
    XCTAssertEqual(text(wav, at: 8), "WAVE")
    XCTAssertEqual(text(wav, at: 12), "fmt ")
    XCTAssertEqual(integer(wav, at: 16, bytes: 4), 16, "fmt chunk size")
    XCTAssertEqual(integer(wav, at: 20, bytes: 2), 1, "PCM format")
    XCTAssertEqual(integer(wav, at: 22, bytes: 2), 1, "channels")
    XCTAssertEqual(integer(wav, at: 24, bytes: 4), 16_000, "sample rate")
    XCTAssertEqual(integer(wav, at: 28, bytes: 4), 32_000, "byte rate")
    XCTAssertEqual(integer(wav, at: 32, bytes: 2), 2, "block align")
    XCTAssertEqual(integer(wav, at: 34, bytes: 2), 16, "bits per sample")
    XCTAssertEqual(text(wav, at: 36), "data")
    XCTAssertEqual(integer(wav, at: 40, bytes: 4), wav.count - 44, "data chunk size")
  }

  func testToneLastsFiveSecondsAtTheDefaultRate() {
    let wav = CallRingback.ringbackTone()
    XCTAssertEqual(wav.count, 44 + 16_000 * 5 * 2)
    XCTAssertEqual(samples(wav).count, 80_000)
  }

  func testHeaderAndLengthFollowACustomSampleRate() {
    let wav = CallRingback.ringbackTone(sampleRate: 8_000)
    XCTAssertEqual(integer(wav, at: 4, bytes: 4), wav.count - 8)
    XCTAssertEqual(integer(wav, at: 24, bytes: 4), 8_000)
    XCTAssertEqual(integer(wav, at: 28, bytes: 4), 16_000)
    XCTAssertEqual(integer(wav, at: 32, bytes: 2), 2)
    XCTAssertEqual(integer(wav, at: 40, bytes: 4), 8_000 * 5 * 2)
    XCTAssertEqual(wav.count, 44 + 8_000 * 5 * 2)
  }

  func testToneSoundsDuringTheFirstSecondAndIsSilentAfterIt() {
    let pcm = samples(CallRingback.ringbackTone())
    let tone = pcm[0..<16_000]
    let silence = pcm[16_000...]
    XCTAssertGreaterThan(tone.filter { $0 != 0 }.count, 15_800)
    XCTAssertEqual(silence.count, 64_000)
    XCTAssertTrue(silence.allSatisfy { $0 == 0 })
  }

  func testToneIs425HertzAtThirtyPercentOfFullScale() {
    let tone = samples(CallRingback.ringbackTone())[0..<16_000].filter { $0 != 0 }
    let signChanges = zip(tone, tone.dropFirst()).filter { ($0 > 0) != ($1 > 0) }.count
    XCTAssertEqual(Double(signChanges + 1) / 2, 425, accuracy: 1)
    let peak = tone.map { abs(Int($0)) }.max() ?? 0
    XCTAssertEqual(peak, Int(Double(Int16.max) * 0.3), accuracy: 1)
  }

  func testToneFadesInFromSilence() {
    let pcm = samples(CallRingback.ringbackTone())
    let fade = 16_000 / 50
    let peak = Double(Int16.max) * 0.3
    XCTAssertEqual(pcm[0], 0)
    XCTAssertLessThan(abs(Int(pcm[1])), 10)
    for index in 0..<fade {
      XCTAssertLessThanOrEqual(
        abs(Int(pcm[index])), Int(peak * Double(index) / Double(fade)) + 1, "sample \(index)")
    }
    let early = pcm[0..<fade / 10].map { abs(Int($0)) }.max() ?? 0
    let settled = pcm[fade..<2 * fade].map { abs(Int($0)) }.max() ?? 0
    XCTAssertLessThan(early, Int(peak) / 5)
    XCTAssertGreaterThan(settled, Int(peak * 0.95))
  }

  func testToneFadesOutBeforeTheSilence() {
    let pcm = samples(CallRingback.ringbackTone())
    let fade = 16_000 / 50
    let peak = Double(Int16.max) * 0.3
    XCTAssertEqual(pcm[15_999], 0)
    for distance in 0..<fade {
      XCTAssertLessThanOrEqual(
        abs(Int(pcm[15_999 - distance])), Int(peak * Double(distance) / Double(fade)) + 1,
        "sample \(15_999 - distance)")
    }
  }

  func testAudioPlayerReadsTheToneAsFiveSecondsOfMonoAudio() throws {
    let player = try AVAudioPlayer(
      data: CallRingback.ringbackTone(), fileTypeHint: AVFileType.wav.rawValue)
    XCTAssertEqual(player.duration, 5, accuracy: 0.01)
    XCTAssertEqual(player.numberOfChannels, 1)
    XCTAssertEqual(player.format.sampleRate, 16_000)
  }
}

private func text(_ data: Data, at offset: Int) -> String {
  let start = data.startIndex + offset
  return String(decoding: data[start..<start + 4], as: UTF8.self)
}

private func integer(_ data: Data, at offset: Int, bytes: Int) -> Int {
  let start = data.startIndex + offset
  return (0..<bytes).reduce(0) { value, byte in
    value | Int(data[start + byte]) << (8 * byte)
  }
}

private func samples(_ wav: Data) -> [Int16] {
  stride(from: 44, to: wav.count, by: 2).map {
    Int16(bitPattern: UInt16(integer(wav, at: $0, bytes: 2)))
  }
}
