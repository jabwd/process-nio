//
//  ProcessNIO.swift
//  
//
//  Created by Antwan van Houdt on 12/10/2021.
//

#if os(Linux)
@_exported import Glibc
#else
@_exported import Darwin
#endif
import NIO

public typealias SigactionHandler = @convention(c)(Int32, UnsafeMutablePointer<siginfo_t>?, UnsafeMutableRawPointer?) -> Void

public final class ProcessNIO {
  public let channel: Channel
  private(set) var pid: Int32?
  private let readDescriptor: Int32
  private let writeDescriptor: Int32
  private let arguments: [String]
  private let path: String

  public static func findPathFor(name: String) -> String? {
    return nil
  }

  public init(
    path: String,
    args: [String],
    eventLoopGroup: EventLoopGroup,
    onRead readHandler: ProcessOutputHandler? = nil
  ) throws {
    var fileDescriptors: [Int32] = [Int32](repeating: 0, count: 2)
    pipe(&fileDescriptors)
    readDescriptor = fileDescriptors[0]
    writeDescriptor = fileDescriptors[1]
    self.arguments = args
    self.path = path

    channel = try NIOPipeBootstrap(group: eventLoopGroup)
      .channelOption(ChannelOptions.maxMessagesPerRead, value: 1)
      .channelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
      .channelInitializer({ channel in
        channel.pipeline.addHandler(ProcessChannelHandler(outputHandler: readHandler))
      })
      .withPipes(inputDescriptor: readDescriptor, outputDescriptor: writeDescriptor).wait()
  }

  public func run() throws -> EventLoopFuture<Void> {
#if os(Linux)
    var fileActions = posix_spawn_file_actions_t()
#else
    var fileActions: posix_spawn_file_actions_t?
#endif
    posix_spawn_file_actions_init(&fileActions)
    defer { posix_spawn_file_actions_destroy(&fileActions) }
    posix_spawn_file_actions_adddup2(&fileActions, writeDescriptor, STDERR_FILENO)
    posix_spawn_file_actions_adddup2(&fileActions, writeDescriptor, STDOUT_FILENO)

    let completedArgs = [path] + arguments
    let unsafeArgs = completedArgs.map { $0.withCString(strdup) } + [nil]
    var newPid: Int32 = -1
    let rc = posix_spawn(&newPid, path, &fileActions, nil, unsafeArgs, nil)
    guard rc == 0 else {
      if rc == ENOENT {
        throw ProcessNIOError.fileNotFound
      }
      let err = strerror(rc)
      if let err = err {
        throw ProcessNIOError.spawnFailed(rc, reason: String(cString: err))
      }
      throw ProcessNIOError.spawnFailed(rc, reason: nil)
    }

    pid = newPid
    ProcessManager.shared.register(process: self)
    return channel.closeFuture
  }

  internal func cleanup() {
    _ = channel.close().always { [weak self] _ in
      guard let self = self else {
        return
      }
      close(self.readDescriptor)
      close(self.writeDescriptor)
    }
  }
}
