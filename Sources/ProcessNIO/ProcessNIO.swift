import NIO
import Foundation

public struct ChildProcess {
  static let queue = DispatchQueue(label: "processnio.executionQueue")
  private let process: Process = Process()
  private let pipe = Pipe()

  public static func findURLFor(name: String) -> URL? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    let pipe = Pipe()
    process.standardOutput = pipe
    process.arguments = [
      name
    ]
    try? process.run()
    process.waitUntilExit()
    let result = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let path = String(data: result, encoding: .utf8)?.replacingOccurrences(of: "\n", with: "") else {
      return nil
    }
    if !FileManager.default.fileExists(atPath: path) {
      return nil
    }
    return URL(fileURLWithPath: path)
  }

  public init(executableURL: URL) {
    self.process.executableURL = executableURL
    // self.process.standardOutput = pipe
    // self.process.standardError = pipe
  }

  public init(path: String) {
    print("path")
    self.process.standardOutput = pipe
    self.process.standardError = pipe
  }

  public func run(withArguments args: [String], fileIO: NonBlockingFileIO, on eventLoop: EventLoop, onOutputHandler: @escaping (String?) -> Void) throws -> EventLoopFuture<Void> {
    process.arguments = args
    let nioHandle = NIOFileHandle.init(descriptor: pipe.fileHandleForReading.fileDescriptor)
    ChildProcess.queue.async {
      print("Launching process?")
      process.launch()
      print("Waiting \(String(describing: process.arguments)) \(String(describing: process.executableURL))")
      process.waitUntilExit()
      print("Hi")
    }
    return fileIO.readChunked(
      fileHandle: nioHandle,
      byteCount: 1024*1024*10,
      chunkSize: 1,
      allocator: ByteBufferAllocator.init(),
      eventLoop: eventLoop) { buffer -> EventLoopFuture<Void> in
        print("Got bytes?")
        var readable = buffer
        let bytes = readable.readBytes(length: buffer.readableBytes) ?? []
        let out = String(bytes: bytes, encoding: .utf8)
        onOutputHandler(out)
        return eventLoop.makeSucceededVoidFuture()
      }.flatMapThrowing {
        try nioHandle.close()
      }
  }
}
