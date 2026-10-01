import AVFoundation
import CallKit
import UIKit
import UserNotifications
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

final class OnceCompletionTests: XCTestCase {
  func testTheHandlerRunsOnceWithTheFirstValue() {
    let calls = Recorded<Int>()
    let completion = OnceCompletion<Int> { calls.append($0) }
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
    let calls = Recorded<Int>()
    let completion = OnceCompletion<Int> { calls.append($0) }
    DispatchQueue.concurrentPerform(iterations: 200) { completion($0) }
    XCTAssertEqual(calls.values.count, 1)
  }
}

final class NotificationResponseRouteTests: XCTestCase {
  private let actions: [NotificationAction] = [.open, .dismiss, .reply, .markRead, .other]

  func testActionIdentifiersMapToTheirActions() {
    XCTAssertEqual(NotificationAction(UNNotificationDefaultActionIdentifier), .open)
    XCTAssertEqual(NotificationAction(UNNotificationDismissActionIdentifier), .dismiss)
    XCTAssertEqual(NotificationAction("reply"), .reply)
    XCTAssertEqual(NotificationAction("mark_read"), .markRead)
    for identifier in ["", "accept", "decline", "Reply", "mark-read"] {
      XCTAssertEqual(NotificationAction(identifier), .other, identifier)
    }
  }

  func testOnlyCustomActionsOnLocalNotificationsHoldTheBridgeTask() {
    for action in actions {
      let custom = action != .open && action != .dismiss
      XCTAssertEqual(route(pushed: false, action).holdsBridgeTask, custom, "\(action)")
      XCTAssertFalse(route(pushed: true, action).holdsBridgeTask, "\(action)")
    }
  }

  func testAResponseAPluginHandledNeedsNothingMore() {
    for pushed in [false, true] {
      for action in actions {
        let route = route(pushed: pushed, action, roomId: "!r:x", replyText: "hi")
        XCTAssertEqual(route.outcome(handledByPlugin: true), .handled, "\(pushed) \(action)")
        XCTAssertFalse(route.releasesBridgeTask(handledByPlugin: true), "\(pushed) \(action)")
      }
    }
  }

  func testATapWithARoomNoPluginTookOpensTheRoom() {
    for pushed in [false, true] {
      XCTAssertEqual(
        route(pushed: pushed, .open, roomId: "!r:x").outcome(handledByPlugin: false),
        .openRoom("!r:x"))
    }
  }

  func testATapWithoutARoomNoPluginTookOnlyCompletes() {
    for pushed in [false, true] {
      XCTAssertEqual(route(pushed: pushed, .open).outcome(handledByPlugin: false), .complete)
    }
  }

  func testAReplyNoPluginTookIsReportedAsNotSent() {
    for pushed in [false, true] {
      XCTAssertEqual(
        route(pushed: pushed, .reply, roomId: "!r:x", replyText: " See you soon ")
          .outcome(handledByPlugin: false),
        .replyNotSent)
    }
    XCTAssertEqual(
      route(pushed: false, .reply, replyText: "hi").outcome(handledByPlugin: false), .replyNotSent)
  }

  func testABlankReplyNoPluginTookIsDroppedQuietly() {
    for text in [nil, "", "   ", " \n\t "] {
      XCTAssertEqual(
        route(pushed: false, .reply, roomId: "!r:x", replyText: text)
          .outcome(handledByPlugin: false),
        .complete, "\(String(describing: text))")
    }
  }

  func testOtherActionsNoPluginTookOnlyComplete() {
    for action in [NotificationAction.markRead, .dismiss, .other] {
      for pushed in [false, true] {
        XCTAssertEqual(
          route(pushed: pushed, action, roomId: "!r:x", replyText: "hi")
            .outcome(handledByPlugin: false),
          .complete, "\(pushed) \(action)")
      }
    }
  }

  func testTheBridgeTaskIsReleasedOnlyWhenHeldAndNoPluginTookTheAction() {
    XCTAssertTrue(route(pushed: false, .reply).releasesBridgeTask(handledByPlugin: false))
    XCTAssertTrue(route(pushed: false, .markRead).releasesBridgeTask(handledByPlugin: false))
    XCTAssertFalse(route(pushed: false, .open).releasesBridgeTask(handledByPlugin: false))
    XCTAssertFalse(route(pushed: true, .reply).releasesBridgeTask(handledByPlugin: false))
  }

  func testAPushedNotificationNoPluginPresentedStaysOutOfTheForeground() {
    XCTAssertEqual(NotificationResponseRoute.presentation(pushed: true), [])
  }

  func testALocalNotificationNoPluginPresentedShowsABannerAndAListEntry() {
    XCTAssertEqual(NotificationResponseRoute.presentation(pushed: false), [.banner, .list])
  }

  func testTheRoomComesFromTheRoomIdFirst() {
    let userInfo: [AnyHashable: Any] = [
      "room_id": "!pushed:x", "payload": #"{"type":"message","roomId":"!local:x"}"#,
    ]
    XCTAssertEqual(NotificationResponseRoute.roomId(in: userInfo), "!pushed:x")
  }

  func testTheRoomComesFromAMessagePayload() {
    let userInfo: [AnyHashable: Any] = [
      "payload": #"{"type":"message","roomId":"!r:x","eventId":"$e"}"#
    ]
    XCTAssertEqual(NotificationResponseRoute.roomId(in: userInfo), "!r:x")
  }

  func testAPayloadThatIsNotAMessageHasNoRoom() {
    let payloads: [Any] = [
      #"{"type":"newDevice","deviceId":"D","roomId":"!r:x"}"#,
      #"{"roomId":"!r:x"}"#,
      #"{"type":"message","roomId":7}"#,
      #"["message","!r:x"]"#,
      "not json",
      "",
      42,
    ]
    for payload in payloads {
      XCTAssertNil(NotificationResponseRoute.roomId(in: ["payload": payload]), "\(payload)")
    }
    XCTAssertNil(NotificationResponseRoute.roomId(in: [:]))
    XCTAssertNil(NotificationResponseRoute.roomId(in: ["room_id": 7]))
  }

  private func route(
    pushed: Bool, _ action: NotificationAction, roomId: String? = nil, replyText: String? = nil
  ) -> NotificationResponseRoute {
    NotificationResponseRoute(pushed: pushed, action: action, roomId: roomId, replyText: replyText)
  }
}

final class ReplyNotSentNoticeTests: XCTestCase {
  func testTheNoticeKeepsTheConversationTitleAndThread() {
    let notice = ReplyNotSentNotice.request(
      title: "Maya", threadIdentifier: "!r:x", roomId: "!r:x")
    XCTAssertEqual(notice.content.title, "Maya")
    XCTAssertEqual(notice.content.threadIdentifier, "!r:x")
  }

  func testTheNoticeSaysWhatHappenedAndWhatToDo() {
    let notice = ReplyNotSentNotice.request(title: "Maya", threadIdentifier: "", roomId: nil)
    XCTAssertEqual(notice.content.body, "Message not sent. Open Zuno and send it again.")
  }

  func testTappingTheNoticeOpensItsRoom() {
    let notice = ReplyNotSentNotice.request(title: "Maya", threadIdentifier: "", roomId: "!r:x")
    let roomId = NotificationResponseRoute.roomId(in: notice.content.userInfo)
    XCTAssertEqual(roomId, "!r:x")
    let tap = NotificationResponseRoute(
      pushed: false, action: .open, roomId: roomId, replyText: nil)
    XCTAssertEqual(tap.outcome(handledByPlugin: false), .openRoom("!r:x"))
  }

  func testANewNoticeForTheSameRoomReplacesTheLastOne() {
    let first = ReplyNotSentNotice.request(title: "A", threadIdentifier: "", roomId: "!a:x")
    let again = ReplyNotSentNotice.request(title: "A", threadIdentifier: "", roomId: "!a:x")
    let other = ReplyNotSentNotice.request(title: "B", threadIdentifier: "", roomId: "!b:x")
    XCTAssertEqual(first.identifier, again.identifier)
    XCTAssertNotEqual(first.identifier, other.identifier)
  }

  func testANoticeWithoutARoomStandsAloneAndOpensNothing() {
    let first = ReplyNotSentNotice.request(title: "A", threadIdentifier: "", roomId: nil)
    let second = ReplyNotSentNotice.request(title: "A", threadIdentifier: "", roomId: nil)
    XCTAssertNotEqual(first.identifier, second.identifier)
    XCTAssertTrue(first.content.userInfo.isEmpty)
  }

  func testTheNoticeArrivesAtOnceWithoutSoundOrActions() {
    let notice = ReplyNotSentNotice.request(title: "A", threadIdentifier: "", roomId: "!a:x")
    XCTAssertNil(notice.trigger)
    XCTAssertNil(notice.content.sound)
    XCTAssertEqual(notice.content.categoryIdentifier, "")
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

  func testADartLockTakesOverTheResponseHoldWithoutAGap() {
    let harness = WakeLockHarness()
    harness.ledger.holdResponse(timeoutMs: 10_000)
    harness.ledger.acquire("message_action", timeoutMs: 30_000)
    XCTAssertEqual(
      harness.tasks.events,
      ["begin zuno:notification_response #1", "begin zuno:message_action #2", "end #1"])
    XCTAssertEqual(harness.ledger.heldTags, ["message_action"])
    XCTAssertEqual(harness.timers.pendingDelays, [30_000])
  }

  func testAcquiringTheResponseTagKeepsItHeld() {
    let harness = WakeLockHarness()
    harness.ledger.acquire(WakeLockLedger.responseTag, timeoutMs: 10_000)
    XCTAssertEqual(harness.ledger.heldTags, [WakeLockLedger.responseTag])
    XCTAssertEqual(harness.tasks.running, [1])
  }

  func testReleasingTheResponseHoldEndsIt() {
    let harness = WakeLockHarness()
    harness.ledger.holdResponse(timeoutMs: 10_000)
    harness.ledger.release(WakeLockLedger.responseTag)
    XCTAssertEqual(harness.tasks.running, [])
    XCTAssertTrue(harness.timers.pendingDelays.isEmpty)
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

final class RoomLaunchStateTests: XCTestCase {
  func testARoomOpenedBeforeAnyEngineWaitsForTheLaunch() {
    var state = RoomLaunchState()
    XCTAssertFalse(state.open("!r:x"))
    let engine = state.attach()
    XCTAssertEqual(state.take(engine), "!r:x")
    XCTAssertNil(state.pendingRoomId)
  }

  func testTheLatestRoomWinsWhileNobodyListens() {
    var state = RoomLaunchState()
    let engine = state.attach()
    XCTAssertFalse(state.open("!a:x"))
    XCTAssertFalse(state.open("!b:x"))
    XCTAssertEqual(state.take(engine), "!b:x")
  }

  func testOnceTheAppTookTheLaunchRoomOpensAreDelivered() {
    var state = RoomLaunchState()
    let engine = state.attach()
    XCTAssertNil(state.take(engine))
    XCTAssertTrue(state.open("!r:x"))
    XCTAssertNil(state.pendingRoomId)
  }

  func testTheLaunchRoomIsHandedOutOnce() {
    var state = RoomLaunchState()
    let engine = state.attach()
    _ = state.open("!r:x")
    XCTAssertEqual(state.take(engine), "!r:x")
    XCTAssertNil(state.take(engine))
  }

  func testANewEngineTakesTheLaunchBeforeRoomsAreDelivered() {
    var state = RoomLaunchState()
    let first = state.attach()
    _ = state.take(first)
    let second = state.attach()
    XCTAssertFalse(state.open("!r:x"))
    XCTAssertEqual(state.take(second), "!r:x")
    XCTAssertTrue(state.open("!s:x"))
  }

  func testAnOlderEngineCannotTakeThePendingRoom() {
    var state = RoomLaunchState()
    let first = state.attach()
    let second = state.attach()
    _ = state.open("!r:x")
    XCTAssertNil(state.take(first))
    XCTAssertEqual(state.pendingRoomId, "!r:x")
    XCTAssertFalse(state.open("!r:x"))
    XCTAssertEqual(state.take(second), "!r:x")
  }

  func testRoomsOpenedAfterTheListeningEngineDetachedWait() {
    var state = RoomLaunchState()
    let engine = state.attach()
    _ = state.take(engine)
    state.detach(engine)
    XCTAssertFalse(state.open("!r:x"))
    XCTAssertEqual(state.pendingRoomId, "!r:x")
  }

  func testAnOlderEngineDetachingKeepsTheNewListener() {
    var state = RoomLaunchState()
    let first = state.attach()
    let second = state.attach()
    _ = state.take(second)
    state.detach(first)
    XCTAssertTrue(state.open("!r:x"))
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

private final class Recorded<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [Value] = []

  var values: [Value] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  func append(_ value: Value) {
    lock.lock()
    recorded.append(value)
    lock.unlock()
  }
}

@MainActor
private final class FakeTimers {
  private final class Entry {
    let milliseconds: Int
    let fire: @MainActor @Sendable () -> Void
    var done = false

    init(milliseconds: Int, fire: @escaping @MainActor @Sendable () -> Void) {
      self.milliseconds = milliseconds
      self.fire = fire
    }
  }

  private var entries: [Entry] = []

  var pendingDelays: [Int] { entries.filter { !$0.done }.map(\.milliseconds) }

  func schedule(
    _ milliseconds: Int, _ fire: @escaping @MainActor @Sendable () -> Void
  ) -> @MainActor () -> Void {
    let entry = Entry(milliseconds: milliseconds, fire: fire)
    entries.append(entry)
    return { entry.done = true }
  }

  func fire(_ index: Int, evenIfCancelled: Bool = false) {
    let entry = entries[index]
    guard evenIfCancelled || !entry.done else { return }
    entry.done = true
    entry.fire()
  }
}

@MainActor
private final class FakeBackgroundTasks {
  private var expirations: [Int: @MainActor @Sendable () -> Void] = [:]
  private var next = 0
  private(set) var events: [String] = []
  private(set) var running: [Int] = []
  var refuses = false

  func begin(_ name: String, _ expired: @escaping @MainActor @Sendable () -> Void) -> Int? {
    guard !refuses else { return nil }
    next += 1
    expirations[next] = expired
    running.append(next)
    events.append("begin \(name) #\(next)")
    return next
  }

  func end(_ task: Int) {
    running.removeAll { $0 == task }
    events.append("end #\(task)")
  }

  func expire(_ task: Int) {
    expirations[task]?()
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
