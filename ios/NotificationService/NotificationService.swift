import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
  private static let deadlineSeconds: Double = 25
  private var sink: NseContentSink?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    let sink = NseContentSink(
      original: request.content,
      remove: {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: $0)
      },
      handler: contentHandler)
    self.sink = sink
    guard let environment = NseLive.environment() else {
      sink.finish(.passthrough)
      return
    }
    let push = NsePush(
      id: request.identifier, userInfo: request.content.userInfo,
      receivedMs: Int64(Date().timeIntervalSince1970 * 1000))
    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.deadlineSeconds) {
      sink.finish(nil)
    }
    Task.detached(priority: .userInitiated) {
      let result = await NsePipeline(env: environment).run(push) { sink.offer($0) }
      sink.finish(result.delivery)
    }
  }

  override func serviceExtensionTimeWillExpire() {
    sink?.finish(nil)
  }
}
