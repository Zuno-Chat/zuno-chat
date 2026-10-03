@preconcurrency import CallKit
@preconcurrency import Flutter
import UIKit

@MainActor
protocol CallProviding: AnyObject {
  func setConfiguration(_ configuration: CXProviderConfiguration)
  func reportNewIncomingCall(
    _ uuid: UUID, update: CXCallUpdate,
    completion: @escaping @MainActor @Sendable ((any Error)?) -> Void)
  func reportUpdate(_ uuid: UUID, _ update: CXCallUpdate)
  func reportEnded(_ uuid: UUID, reason: CXCallEndedReason)
  func reportOutgoingStarted(_ uuid: UUID)
  func reportOutgoingConnected(_ uuid: UUID)
  func invalidate()
}

@MainActor
final class SystemCallProvider: CallProviding {
  private let provider: CXProvider

  init(configuration: CXProviderConfiguration, delegate: any CXProviderDelegate) {
    provider = CXProvider(configuration: configuration)
    provider.setDelegate(delegate, queue: .main)
  }

  func setConfiguration(_ configuration: CXProviderConfiguration) {
    provider.configuration = configuration
  }

  func reportNewIncomingCall(
    _ uuid: UUID, update: CXCallUpdate,
    completion: @escaping @MainActor @Sendable ((any Error)?) -> Void
  ) {
    provider.reportNewIncomingCall(with: uuid, update: update) { error in
      let box = UncheckedSendable(error)
      Task { @MainActor in completion(box.value) }
    }
  }

  func reportUpdate(_ uuid: UUID, _ update: CXCallUpdate) {
    provider.reportCall(with: uuid, updated: update)
  }

  func reportEnded(_ uuid: UUID, reason: CXCallEndedReason) {
    provider.reportCall(with: uuid, endedAt: nil, reason: reason)
  }

  func reportOutgoingStarted(_ uuid: UUID) {
    provider.reportOutgoingCall(with: uuid, startedConnectingAt: nil)
  }

  func reportOutgoingConnected(_ uuid: UUID) {
    provider.reportOutgoingCall(with: uuid, connectedAt: nil)
  }

  func invalidate() {
    provider.invalidate()
  }
}

@MainActor
protocol AnswerActionHandle: AnyObject {
  var actionId: UUID { get }
  var timeoutDate: Date { get }
  func fulfill()
  func fail()
}

extension CXAnswerCallAction: AnswerActionHandle {
  var actionId: UUID { uuid }
}

@MainActor
protocol CallEventSink: AnyObject {
  func send(_ method: String, _ arguments: [String: Any])
}

extension FlutterMethodChannel: CallEventSink {
  func send(_ method: String, _ arguments: [String: Any]) {
    invokeMethod(method, arguments: arguments)
  }
}
