@preconcurrency import Flutter
import Network
import UIKit

@MainActor
final class NetworkPlugin: NSObject, @preconcurrency FlutterStreamHandler {
  private var monitor: NWPathMonitor?
  private var sink: FlutterEventSink?
  private var reported: Bool?
  private var generation = 0

  static func register(with registrar: FlutterPluginRegistrar) {
    FlutterEventChannel(name: "zuno/network", binaryMessenger: registrar.messenger())
      .setStreamHandler(NetworkPlugin())
  }

  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    stop()
    generation += 1
    let listening = generation
    sink = events
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      let available = path.status != .unsatisfied
      MainActor.assumeIsolated { self?.report(available, for: listening) }
    }
    self.monitor = monitor
    monitor.start(queue: .main)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stop()
    return nil
  }

  private func report(_ available: Bool, for listening: Int) {
    guard listening == generation, reported != available, let sink else { return }
    reported = available
    sink(available)
  }

  private func stop() {
    monitor?.cancel()
    monitor = nil
    sink = nil
    reported = nil
  }
}
