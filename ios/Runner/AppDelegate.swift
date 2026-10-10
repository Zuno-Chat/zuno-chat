import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    PushRingHandler.shared.start()
    NseAppHooks.shared.start()
    NotifySweep.shared.runWhenProtectedDataAvailable()
    excludeAppDataFromBackup()
    Self.wireCallKit(CallKitCenter.shared, to: ReadModelCache.shared)
    CallKitCenter.shared.setUp()
    MetricsSubscriber.shared.start()
    UNUserNotificationCenter.current().delegate = self
    NotificationCategories.register()
    NotificationCenter.default.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { _ in
      UNUserNotificationCenter.current().removeDeliveredNotifications(
        withIdentifiers: [CatchUpComposer.overflowIdentifier])
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping @Sendable (UNNotificationPresentationOptions) -> Void
  ) {
    if let early = NotificationResponseRoute.earlyPresentation(
      identifier: notification.request.identifier,
      userInfo: notification.request.content.userInfo)
    {
      completionHandler(early)
      return
    }
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
    let action = NotificationAction(response.actionIdentifier)
    if action.isCustom {
      routeNotificationAction(response, action: action, then: completionHandler)
      return
    }
    let completion = OnceCompletion<Void> { _ in completionHandler() }
    let route = NotificationResponseRoute(
      action: action,
      roomId: NotificationResponseRoute.roomId(
        in: response.notification.request.content.userInfo))
    super.userNotificationCenter(center, didReceive: response) { completion(()) }
    switch route.outcome(handledByPlugin: completion.isDone) {
    case .handled:
      return
    case .complete:
      completion(())
    case .openRoom(let roomId):
      RoomLaunchPlugin.open(roomId)
      completion(())
    }
  }

  private func routeNotificationAction(
    _ response: UNNotificationResponse, action: NotificationAction,
    then completionHandler: @escaping @Sendable () -> Void
  ) {
    let completion = OnceCompletion<Void> { _ in completionHandler() }
    let request = response.notification.request
    let decision = NotificationActionPlanner.decide(
      action: action, notificationId: request.identifier, title: request.content.title,
      thread: request.content.threadIdentifier, userInfo: request.content.userInfo,
      replyText: (response as? UNTextInputNotificationResponse)?.userText,
      unlocked: FirstUnlockProbe.passed() && ProtectedData.isAvailable(),
      makeId: { UUID().uuidString })
    switch decision {
    case .complete:
      completion(())
    case .replyNotSent(let notice):
      NotificationActionEffects.reportNotSent(notice) { completion(()) }
    case .enqueue(let actionRequest):
      NotificationActionsPlugin.inbox.accept(actionRequest) { completion(()) }
      _ = EngineHost.shared.start(.action)
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

  static func wireCallKit(_ calls: CallKitCenter, to cache: ReadModelCache) {
    calls.onLedger = { cache.record($0) }
    calls.roomToken = { cache.roomToken($0) }
    calls.previewLevel = { cache.meta()?.level ?? .full }
    calls.isResolved = { cache.ledger().isResolved($0) }
    calls.ringFlag = { cache.ringFlag() }
    calls.onUnboundAnswerExpired = { source in
      if source == .bfu { MissedCallNotice.post() }
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
}

struct NotificationResponseRoute: Equatable, Sendable {
  let action: NotificationAction
  let roomId: String?

  func outcome(handledByPlugin: Bool) -> NotificationResponseOutcome {
    if handledByPlugin { return .handled }
    guard action == .open, let roomId else { return .complete }
    return .openRoom(roomId)
  }

  static func presentation(pushed: Bool) -> UNNotificationPresentationOptions {
    pushed ? [] : [.banner, .list]
  }

  static func earlyPresentation(identifier: String, userInfo: [AnyHashable: Any])
    -> UNNotificationPresentationOptions?
  {
    if CatchUpComposer.isCatchUp(identifier) { return [] }
    if userInfo["test"] as? String == "1"
      || (userInfo["event_id"] as? String)?.hasPrefix(NsePush.testPrefix) == true
    {
      return [.banner, .list, .sound]
    }
    return nil
  }

  static func roomId(
    in userInfo: [AnyHashable: Any], resolveToken: (String) -> String? = NseRoomLookup.roomId
  ) -> String? {
    NotificationUserInfo.text(userInfo["room_id"])
      ?? NseRoomLookup.target(in: userInfo, resolve: resolveToken)
      ?? NotificationUserInfo.text(NotificationUserInfo.messagePayload(in: userInfo)?["roomId"])
  }
}
