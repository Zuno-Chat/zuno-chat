import Flutter
import UIKit
import UserNotifications
import flutter_local_notifications
import flutter_secure_storage_darwin
import os
import package_info_plus
import shared_preferences_foundation
import sqflite_sqlcipher

@main
@objc class AppDelegate: FlutterAppDelegate, @preconcurrency FlutterImplicitEngineDelegate {
  nonisolated private static let log = Logger(
    subsystem: "im.zuno.chat", category: "notifications")

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeAppDataFromBackup()
    CallKitCenter.shared.setUp()
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      MainActor.assumeIsolated {
        AppDelegate.registerActionEnginePlugins(in: registry)
      }
    }
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping @Sendable (UNNotificationPresentationOptions) -> Void
  ) {
    let completion = OnceCompletion(completionHandler)
    super.userNotificationCenter(center, willPresent: notification) { completion($0) }
    guard !completion.isDone else { return }
    completion(
      NotificationResponseRoute.presentation(
        pushed: notification.request.trigger is UNPushNotificationTrigger))
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping @Sendable () -> Void
  ) {
    let completion = OnceCompletion<Void> { _ in completionHandler() }
    let request = response.notification.request
    let route = NotificationResponseRoute(
      pushed: request.trigger is UNPushNotificationTrigger,
      action: NotificationAction(response.actionIdentifier),
      roomId: NotificationResponseRoute.roomId(in: request.content.userInfo),
      replyText: (response as? UNTextInputNotificationResponse)?.userText)
    if route.holdsBridgeTask {
      WakeLockPlugin.holdForNotificationResponse()
    }
    super.userNotificationCenter(center, didReceive: response) { completion(()) }
    let handled = completion.isDone
    let finish: @MainActor @Sendable () -> Void = {
      if route.releasesBridgeTask(handledByPlugin: handled) {
        WakeLockPlugin.releaseNotificationResponse()
      }
      completion(())
    }
    switch route.outcome(handledByPlugin: handled) {
    case .handled:
      return
    case .complete:
      finish()
    case .openRoom(let roomId):
      RoomLaunchPlugin.open(roomId)
      finish()
    case .replyNotSent:
      Self.reportReplyNotSent(after: request.content, roomId: route.roomId, then: finish)
    }
  }

  private static func reportReplyNotSent(
    after original: UNNotificationContent, roomId: String?,
    then finish: @escaping @MainActor @Sendable () -> Void
  ) {
    let notice = ReplyNotSentNotice.request(
      title: original.title, threadIdentifier: original.threadIdentifier, roomId: roomId)
    UNUserNotificationCenter.current().add(notice) { error in
      if let error {
        log.error("reply-not-sent notice failed: \(error.localizedDescription, privacy: .public)")
      }
      Task { @MainActor in finish() }
    }
  }

  private static func registerActionEnginePlugins(in registry: FlutterPluginRegistry) {
    let plugins: [(key: String, type: FlutterPlugin.Type)] = [
      ("FlutterLocalNotificationsPlugin", FlutterLocalNotificationsPlugin.self),
      ("FlutterSecureStorageDarwinPlugin", FlutterSecureStorageDarwinPlugin.self),
      ("FPPPackageInfoPlusPlugin", FPPPackageInfoPlusPlugin.self),
      ("SharedPreferencesPlugin", SharedPreferencesPlugin.self),
      ("SqfliteSqlCipherPlugin", SqfliteSqlCipherPlugin.self),
      ("ZunoWakeLockPlugin", WakeLockPlugin.self),
      ("ZunoClientLeasePlugin", ClientLeasePlugin.self),
    ]
    for plugin in plugins {
      if let registrar = registry.registrar(forPlugin: plugin.key) {
        plugin.type.register(with: registrar)
      }
    }
  }

  private func excludeAppDataFromBackup() {
    let files = FileManager.default
    for directory in [
      FileManager.SearchPathDirectory.applicationSupportDirectory, .documentDirectory,
    ] {
      guard var url = files.urls(for: directory, in: .userDomainMask).first else { continue }
      try? files.createDirectory(at: url, withIntermediateDirectories: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? url.setResourceValues(values)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registry = engineBridge.pluginRegistry
    GeneratedPluginRegistrant.register(with: registry)
    CallKitCenter.shared.audio.adoptRegisteredWebRTC()
    if let registrar = registry.registrar(forPlugin: "ZunoApnsPlugin") {
      ApnsTokenPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoVideoToolsPlugin") {
      VideoToolsPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoImageResizerPlugin") {
      ImageResizerPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoAppDataPlugin") {
      AppDataPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoCallsChannelPlugin") {
      CallsChannelPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoUploadServicePlugin") {
      UploadServicePlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoNetworkPlugin") {
      NetworkPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoRoomLaunchPlugin") {
      RoomLaunchPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoShareInboxPlugin") {
      ShareInboxPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoWakeLockPlugin") {
      WakeLockPlugin.register(with: registrar)
    }
    if let registrar = registry.registrar(forPlugin: "ZunoClientLeasePlugin") {
      ClientLeasePlugin.register(with: registrar)
    }
  }
}

final class OnceCompletion<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var handler: (@Sendable (Value) -> Void)?

  init(_ handler: @escaping @Sendable (Value) -> Void) {
    self.handler = handler
  }

  var isDone: Bool {
    lock.lock()
    defer { lock.unlock() }
    return handler == nil
  }

  func callAsFunction(_ value: Value) {
    lock.lock()
    let pending = handler
    handler = nil
    lock.unlock()
    pending?(value)
  }
}

enum NotificationAction: Equatable, Sendable {
  case open
  case dismiss
  case reply
  case markRead
  case other

  init(_ identifier: String) {
    switch identifier {
    case UNNotificationDefaultActionIdentifier: self = .open
    case UNNotificationDismissActionIdentifier: self = .dismiss
    case "reply": self = .reply
    case "mark_read": self = .markRead
    default: self = .other
    }
  }

  var isCustom: Bool { self != .open && self != .dismiss }
}

enum NotificationResponseOutcome: Equatable, Sendable {
  case handled
  case complete
  case openRoom(String)
  case replyNotSent
}

struct NotificationResponseRoute: Equatable, Sendable {
  let pushed: Bool
  let action: NotificationAction
  let roomId: String?
  let replyText: String?

  var holdsBridgeTask: Bool { !pushed && action.isCustom }

  func releasesBridgeTask(handledByPlugin: Bool) -> Bool {
    holdsBridgeTask && !handledByPlugin
  }

  func outcome(handledByPlugin: Bool) -> NotificationResponseOutcome {
    if handledByPlugin { return .handled }
    switch action {
    case .open:
      guard let roomId else { return .complete }
      return .openRoom(roomId)
    case .reply:
      let text = replyText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return text.isEmpty ? .complete : .replyNotSent
    case .dismiss, .markRead, .other:
      return .complete
    }
  }

  static func presentation(pushed: Bool) -> UNNotificationPresentationOptions {
    pushed ? [] : [.banner, .list]
  }

  static func roomId(in userInfo: [AnyHashable: Any]) -> String? {
    if let roomId = userInfo["room_id"] as? String { return roomId }
    guard let payload = userInfo["payload"] as? String,
      let decoded = try? JSONSerialization.jsonObject(with: Data(payload.utf8)),
      let message = decoded as? [String: Any],
      message["type"] as? String == "message"
    else { return nil }
    return message["roomId"] as? String
  }
}

enum ReplyNotSentNotice {
  static let body = "Message not sent. Open Zuno and send it again."

  static func request(title: String, threadIdentifier: String, roomId: String?)
    -> UNNotificationRequest
  {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.threadIdentifier = threadIdentifier
    if let roomId {
      content.userInfo = ["room_id": roomId]
    }
    return UNNotificationRequest(
      identifier: "zuno.reply_not_sent.\(roomId ?? UUID().uuidString)", content: content,
      trigger: nil)
  }
}
