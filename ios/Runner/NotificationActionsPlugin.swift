@preconcurrency import Flutter
import UIKit
import UserNotifications
import os

@MainActor
enum NotificationActionsCommand {
  enum Reply {
    case actions([[String: Any]])
    case done
    case badArguments
    case notImplemented
  }

  static func handle(_ method: String, _ arguments: Any?, inbox: NotificationActionInbox) -> Reply {
    switch method {
    case "takeActions":
      return .actions(inbox.take().map(\.channelValue))
    case "finish":
      guard let arguments = arguments as? [String: Any],
        let id = arguments["id"] as? String, !id.isEmpty
      else { return .badArguments }
      inbox.finish(id, ok: arguments["ok"] as? Bool ?? false)
      return .done
    default:
      return .notImplemented
    }
  }
}

@MainActor
enum NotificationActionEffects {
  nonisolated private static let log = Logger(
    subsystem: "im.zuno.chat", category: "notification-actions")

  static func reportNotSent(
    _ notice: NotificationActionNotice, then done: @escaping @MainActor @Sendable () -> Void
  ) {
    UNUserNotificationCenter.current().add(ReplyNotSentNotice.request(for: notice)) { error in
      if let error {
        log.error("reply-not-sent notice failed: \(error.localizedDescription, privacy: .public)")
      }
      Task { @MainActor in done() }
    }
  }

  nonisolated static func identifiersToTakeDown(
    _ request: NotificationActionRequest, delivered notes: [DeliveredNote]
  ) -> [String] {
    let acted = request.notice.notificationId
    guard let seconds = request.eventSeconds else { return [acted] }
    let token = request.notice.roomToken ?? request.notice.thread
    let reads = [ThreadRead(token: token, upToMs: Int64(seconds) * 1000 + 999)]
    return DeliveredSweep.identifiersToRemove(notes, reads: reads) + [acted]
  }

  static func takeDownRead(_ request: NotificationActionRequest) {
    UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
      let notes = notifications.map {
        DeliveredNote(
          identifier: $0.request.identifier, thread: $0.request.content.threadIdentifier,
          userInfo: $0.request.content.userInfo,
          pushed: $0.request.trigger is UNPushNotificationTrigger)
      }
      UNUserNotificationCenter.current().removeDeliveredNotifications(
        withIdentifiers: identifiersToTakeDown(request, delivered: notes))
    }
  }
}

@MainActor
final class NotificationActionsPlugin: NSObject, @preconcurrency FlutterPlugin {
  static let inbox = NotificationActionInbox(
    begin: { name, expired in
      let task = UIApplication.shared.beginBackgroundTask(withName: name) { expired() }
      return task == .invalid ? nil : task.rawValue
    },
    end: { UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: $0)) },
    schedule: MainActorTimer.schedule,
    notSent: NotificationActionEffects.reportNotSent,
    markedRead: NotificationActionEffects.takeDownRead)

  private static weak var listener: NotificationActionsPlugin?

  private let channel: FlutterMethodChannel

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "zuno/notification_actions", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(NotificationActionsPlugin(channel: channel), channel: channel)
    inbox.onAccepted = {
      listener?.channel.invokeMethod("actionsAvailable", arguments: nil)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch NotificationActionsCommand.handle(call.method, call.arguments, inbox: Self.inbox) {
    case .actions(let actions):
      Self.listener = self
      result(actions)
    case .done:
      result(nil)
    case .badArguments:
      result(
        FlutterError(code: "bad_arguments", message: "finish needs an action id", details: nil))
    case .notImplemented:
      result(FlutterMethodNotImplemented)
    }
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    if Self.listener === self { Self.listener = nil }
  }
}

extension ReplyNotSentNotice {
  static func request(for notice: NotificationActionNotice) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = notice.title
    content.body = body
    content.threadIdentifier = notice.thread
    if let token = notice.roomToken {
      content.userInfo = ["t": token]
    } else if let roomId = notice.roomId {
      content.userInfo = ["room_id": roomId]
    }
    let key = notice.roomToken ?? notice.roomId ?? UUID().uuidString
    return UNNotificationRequest(
      identifier: ReplyNotSentNotice.identifierPrefix + key, content: content, trigger: nil)
  }
}
