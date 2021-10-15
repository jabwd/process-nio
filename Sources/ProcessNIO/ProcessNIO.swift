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

extension String {
  static func errno(_ errnum: Int32) -> String? {
    if let err = strerror(errnum) {
      return String(cString: err)
    }
    return nil
  }
}

public enum ProcessPath {
  case path(String)
  case name(String)
}

public typealias SigactionHandler = @convention(c)(Int32, UnsafeMutablePointer<siginfo_t>?, UnsafeMutableRawPointer?) -> Void

public final class ProcessNIO {
  internal private(set) var channel: Channel?
  private(set) var pid: Int32?
  public internal(set) var terminationStatus: Int32?
  private let readDescriptor: Int32
  private let writeDescriptor: Int32
  private let arguments: [String]
  private let pathName: ProcessPath
  private let eventLoopGroup: EventLoopGroup

  public init(
    _ pathName: ProcessPath,
    arguments: [String],
    eventLoopGroup: EventLoopGroup
  ) {
    var fileDescriptors: [Int32] = [Int32](repeating: 0, count: 2)
    pipe(&fileDescriptors)
    readDescriptor = fileDescriptors[0]
    writeDescriptor = fileDescriptors[1]
    self.arguments = arguments
    self.pathName = pathName
    self.eventLoopGroup = eventLoopGroup
  }

  deinit {
    cleanup()
  }

  public func run(on eventLoop: EventLoop, onRead readHandler: ProcessOutputHandler? = nil) -> EventLoopFuture<Int32> {
    let channelFuture = NIOPipeBootstrap(group: eventLoopGroup)
      .channelOption(ChannelOptions.maxMessagesPerRead, value: 1)
      .channelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
      .channelInitializer({ channel in
        channel.pipeline.addHandler(ProcessChannelHandler(outputHandler: readHandler))
      })
      .withPipes(inputDescriptor: readDescriptor, outputDescriptor: writeDescriptor)

#if os(Linux)
    var fileActions = posix_spawn_file_actions_t()
#else
    var fileActions: posix_spawn_file_actions_t?
#endif
    posix_spawn_file_actions_init(&fileActions)
    defer { posix_spawn_file_actions_destroy(&fileActions) }
    posix_spawn_file_actions_adddup2(&fileActions, writeDescriptor, STDERR_FILENO)
    posix_spawn_file_actions_adddup2(&fileActions, writeDescriptor, STDOUT_FILENO)

    var newPid: Int32 = -1
    let rc: CInt
    switch pathName {
    case .name(let name):
      // TODO: Figure out if I need the path in the first argument for spawnp too
      //       and if so how to resolve it correctly
      let completedArgs = [CommandLine.arguments.first ?? ""] + arguments
      let unsafeArgs = completedArgs.map { $0.withCString(strdup) } + [nil]
      rc = posix_spawnp(&newPid, name, &fileActions, nil, unsafeArgs, environ)
      break
    case .path(let path):
      let completedArgs = [path] + arguments
      let unsafeArgs = completedArgs.map { $0.withCString(strdup) } + [nil]
      rc = posix_spawn(&newPid, path, &fileActions, nil, unsafeArgs, environ)
      break
    }

    guard rc == 0 else {
      if rc == ENOENT {
        return eventLoop.makeFailedFuture(ProcessNIOError.fileNotFound)
      }
      return eventLoop.makeFailedFuture(ProcessNIOError.spawnFailed(rc, reason: String.errno(rc)))
    }

    pid = newPid
    ProcessManager.shared.register(process: self)

    return channelFuture.flatMap { channel in
      self.channel = channel
      return channel.closeFuture.flatMap { _ -> EventLoopFuture<Int32> in
        guard let status = self.terminationStatus else {
          return channel.eventLoop.makeSucceededFuture(-1)
        }
        guard status == 0 else {
          return channel.eventLoop.makeFailedFuture(ProcessNIOError.nonZeroExit(status))
        }
        return channel.eventLoop.makeSucceededFuture(status)
      }
    }.hop(to: eventLoop)
  }

  internal func cleanup() {
    _ = channel?.close()
  }
}
