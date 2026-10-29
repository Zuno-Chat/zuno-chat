import AVFoundation
import CallKit
@preconcurrency import Flutter
import Foundation

@MainActor
final class ConversationTonesPlugin: NSObject, @preconcurrency FlutterPlugin {
  private lazy var calls = CXCallObserver()
  private var players: [String: AVAudioPlayer] = [:]
  private var unavailable: Set<String> = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "zuno/conversation_tones", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ConversationTonesPlugin(), channel: channel)
  }

  nonisolated static func soundName(for tone: String) -> String? {
    switch tone {
    case "incoming": return "conversation_in"
    case "sent": return "conversation_out"
    default: return nil
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "play",
      let tone = (call.arguments as? [String: Any])?["tone"] as? String,
      let name = Self.soundName(for: tone)
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard !calls.calls.contains(where: { !$0.hasEnded }), let player = player(named: name),
      !player.isPlaying
    else {
      result(nil)
      return
    }
    player.currentTime = 0
    guard player.play() else {
      result(nil)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + player.duration) { result(nil) }
  }

  private func player(named name: String) -> AVAudioPlayer? {
    if let player = players[name] { return player }
    guard !unavailable.contains(name) else { return nil }
    guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else {
      return give(up: name, CocoaError(.fileNoSuchFile))
    }
    do {
      let player = try AVAudioPlayer(contentsOf: url)
      player.prepareToPlay()
      players[name] = player
      return player
    } catch {
      return give(up: name, error)
    }
  }

  private func give(up name: String, _ error: any Error) -> AVAudioPlayer? {
    unavailable.insert(name)
    CaughtErrors.record("conversation tone", error)
    return nil
  }
}
