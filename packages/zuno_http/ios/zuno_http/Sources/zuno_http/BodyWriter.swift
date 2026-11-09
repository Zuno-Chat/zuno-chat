import Foundation

final class UploadRunLoop: NSObject {
  static let shared = UploadRunLoop()

  private var runLoop: CFRunLoop?
  private let started = DispatchSemaphore(value: 0)

  override init() {
    super.init()
    let thread = Thread { [unowned self] in
      let current = RunLoop.current
      current.add(NSMachPort(), forMode: .default)
      self.runLoop = CFRunLoopGetCurrent()
      self.started.signal()
      while true {
        current.run(mode: .default, before: .distantFuture)
      }
    }
    thread.name = "zuno.http.upload"
    thread.start()
    started.wait()
  }

  func perform(_ block: @escaping () -> Void) {
    guard let runLoop else { return }
    CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
    CFRunLoopWakeUp(runLoop)
  }
}

final class BodyWriter: NSObject, StreamDelegate {
  static let bufferSize = 64 * 1024

  let input: InputStream
  private let output: OutputStream
  private let onSpace: () -> Void
  private var pending = Data()
  private var last = false
  private var hasSpace = false
  private var closed = false

  init(onSpace: @escaping () -> Void) {
    var input: InputStream?
    var output: OutputStream?
    Stream.getBoundStreams(
      withBufferSize: BodyWriter.bufferSize, inputStream: &input, outputStream: &output)
    self.input = input!
    self.output = output!
    self.onSpace = onSpace
    super.init()
    self.output.delegate = self
    UploadRunLoop.shared.perform { [self] in
      self.output.schedule(in: .current, forMode: .default)
      self.output.open()
    }
  }

  func write(_ chunk: Data, last: Bool) {
    UploadRunLoop.shared.perform { [self] in
      guard !closed else { return }
      if pending.isEmpty { pending = chunk } else { pending.append(chunk) }
      self.last = last
      flush()
    }
  }

  func close() {
    UploadRunLoop.shared.perform { [self] in finish() }
  }

  func stream(_ stream: Stream, handle event: Stream.Event) {
    switch event {
    case .hasSpaceAvailable:
      hasSpace = true
      flush()
    case .errorOccurred, .endEncountered:
      finish()
    default:
      break
    }
  }

  private func flush() {
    while hasSpace && !pending.isEmpty && !closed {
      let written = pending.withUnsafeBytes { buffer in
        output.write(buffer.bindMemory(to: UInt8.self).baseAddress!, maxLength: buffer.count)
      }
      if written <= 0 {
        hasSpace = false
        break
      }
      pending.removeFirst(written)
      hasSpace = output.hasSpaceAvailable
    }
    guard pending.isEmpty, !closed else { return }
    if last {
      finish()
    } else if hasSpace {
      onSpace()
    }
  }

  private func finish() {
    guard !closed else { return }
    closed = true
    output.close()
    output.remove(from: .current, forMode: .default)
  }
}
