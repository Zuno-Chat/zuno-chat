struct LaunchHandoff<Value: Equatable & Sendable>: Equatable, Sendable {
  private(set) var pending: Value?
  private(set) var listener: Int?
  private var attachments = 0

  mutating func attach() -> Int {
    attachments += 1
    listener = nil
    return attachments
  }

  mutating func detach(_ attachment: Int) {
    if listener == attachment {
      listener = nil
    }
  }

  mutating func offer(_ value: Value) -> Bool {
    guard listener != nil else {
      pending = value
      return false
    }
    return true
  }

  mutating func take(_ attachment: Int) -> Value? {
    guard attachment == attachments else { return nil }
    listener = attachment
    defer { pending = nil }
    return pending
  }
}
