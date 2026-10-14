import Foundation

enum L10n {
  static var appLocale: String { Bundle.main.localizedString(forKey: "l10n_locale", value: "en", table: nil) }
  static var callsGenericRingName: String { text("callsGenericRingName") }
  static var callsIncomingVideo: String { text("callsIncomingVideo") }
  static var callsIncomingVoice: String { text("callsIncomingVoice") }
  static var callsMissedBeforeUnlock: String { text("callsMissedBeforeUnlock") }
  static var callsMissedCallTitle: String { text("callsMissedCallTitle") }
  static var callsScreenCaptureHidden: String { text("callsScreenCaptureHidden") }
  static var callsSummaryDeclinedVideo: String { text("callsSummaryDeclinedVideo") }
  static var callsSummaryDeclinedVoice: String { text("callsSummaryDeclinedVoice") }
  static func callsSummaryEndedVideo(_ duration: String) -> String {
    String.localizedStringWithFormat(L10n.text("callsSummaryEndedVideo"), duration)
  }
  static func callsSummaryEndedVoice(_ duration: String) -> String {
    String.localizedStringWithFormat(L10n.text("callsSummaryEndedVoice"), duration)
  }
  static var callsSummaryMissedVideo: String { text("callsSummaryMissedVideo") }
  static var callsSummaryMissedVoice: String { text("callsSummaryMissedVoice") }
  static var callsVideoCall: String { text("callsVideoCall") }
  static var callsVoiceCall: String { text("callsVoiceCall") }
  static var commonCancel: String { text("commonCancel") }
  static var commonClose: String { text("commonClose") }
  static var commonMarkAsRead: String { text("commonMarkAsRead") }
  static var commonMessageHint: String { text("commonMessageHint") }
  static var commonReply: String { text("commonReply") }
  static var commonSend: String { text("commonSend") }
  static var matrixSharePreparing: String { text("matrixSharePreparing") }
  static var matrixSummaryDeleted: String { text("matrixSummaryDeleted") }
  static var matrixSummaryLiveLocation: String { text("matrixSummaryLiveLocation") }
  static var matrixSummaryLocation: String { text("matrixSummaryLocation") }
  static func matrixSummaryOtherEvent(_ type: String) -> String {
    String.localizedStringWithFormat(L10n.text("matrixSummaryOtherEvent"), type)
  }
  static var matrixSummaryPhoto: String { text("matrixSummaryPhoto") }
  static var matrixSummaryVideo: String { text("matrixSummaryVideo") }
  static var matrixSummaryVoice: String { text("matrixSummaryVoice") }
  static func notificationsInvitedToRoom(_ room: String) -> String {
    String.localizedStringWithFormat(L10n.text("notificationsInvitedToRoom"), room)
  }
  static func notificationsMoreChats(_ count: Int) -> String {
    String.localizedStringWithFormat(L10n.text("notificationsMoreChats"), count)
  }
  static func notificationsMoreChatsAndRooms(_ count: Int) -> String {
    String.localizedStringWithFormat(L10n.text("notificationsMoreChatsAndRooms"), count)
  }
  static func notificationsMoreRooms(_ count: Int) -> String {
    String.localizedStringWithFormat(L10n.text("notificationsMoreRooms"), count)
  }
  static var notificationsNewActivity: String { text("notificationsNewActivity") }
  static var notificationsNewMessage: String { text("notificationsNewMessage") }
  static var notificationsRedacted: String { text("notificationsRedacted") }
  static var notificationsReplyNotSent: String { text("notificationsReplyNotSent") }
  static func notificationsSenderText(_ sender: String, _ text: String) -> String {
    String.localizedStringWithFormat(L10n.text("notificationsSenderText"), sender, text)
  }
  static var notificationsTestWorks: String { text("notificationsTestWorks") }
  static func notificationsUnknownFormat(_ type: String) -> String {
    String.localizedStringWithFormat(L10n.text("notificationsUnknownFormat"), type)
  }
  static var notificationsWantsToVerify: String { text("notificationsWantsToVerify") }
  static var roomsInvitedYouToChat: String { text("roomsInvitedYouToChat") }
  static var shareOpenLater: String { text("shareOpenLater") }
  static var shareUnreadable: String { text("shareUnreadable") }

  private static let missing = "\u{1}"
  private static let english = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main

  private static func text(_ key: String) -> String {
    let localized = Bundle.main.localizedString(forKey: key, value: missing, table: nil)
    return localized == missing ? english.localizedString(forKey: key, value: nil, table: nil) : localized
  }
}
