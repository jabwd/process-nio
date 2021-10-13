//
//  spawn.swift
//  
//
//  Created by Antwan van Houdt on 12/10/2021.
//

#if os(Linux)
import Glibc
#else
import Darwin
#endif
import NIO

typealias SigactionHandler = @convention(c)(Int32, UnsafeMutablePointer<siginfo_t>?, UnsafeMutableRawPointer?) -> Void

public typealias ProcessOutputHandler = (String) -> Void

public final class ProcessChannelHandler: ChannelInboundHandler {
  public typealias InboundIn = ByteBuffer
  public var outputHandler: ProcessOutputHandler?

  init(outputHandler: ProcessOutputHandler? = nil) {
    self.outputHandler = outputHandler
  }

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let inboundData = self.unwrapInboundIn(data)

    guard let str = String(bytes: inboundData.readableBytesView, encoding: .utf8) else {
      return
    }
    outputHandler?(str)
  }
}

public enum ProcessNIOError: Error {
  case spawnFailed(Int32, reason: String?)
  case fileNotFound
}

public final class ProcessManager {
  private var children: [Int32: ProcessNIO] = [:]
  var oldSignalHandlers: [sigaction] = []

  static let shared = ProcessManager()

  init() {
    var action = sigaction()
    let handler: SigactionHandler = { (signo, info, context) in
      guard let info = info else {
        return
      }
      ProcessManager.shared.handleSignal(signo, info, context)
    }
    #if os(Linux)
    action.__sigaction_handler = unsafeBitCast(handler, to: sigaction.__Unnamed_union___sigaction_handler.self)
    #else
    action.__sigaction_u = __sigaction_u.init(__sa_sigaction: handler)
    #endif
    var oldAction = sigaction()
    sigaction(SIGCHLD, &action, &oldAction)
    oldSignalHandlers.append(oldAction)
  }

  internal func register(process: ProcessNIO) {
    guard let pid = process.pid else {
      return
    }
    self.children[pid] = process
  }

  func handleSignal(_ signo: Int32, _ info: UnsafeMutablePointer<siginfo_t>?, _ context: UnsafeMutableRawPointer?) {
    for oldHandler in oldSignalHandlers {
      let oldAction = oldHandler
      #if os(Linux)
      let oldHandler = unsafeBitCast(oldAction.__sigaction_handler, to: SigactionHandler.self)
      #else
      if oldAction.__sigaction_u.__sa_handler == nil && oldAction.__sigaction_u.__sa_sigaction == nil {
        continue
      }
      let oldHandler = unsafeBitCast(oldAction.__sigaction_u, to: SigactionHandler.self)
      #endif
      oldHandler(signo, info, context)
    }
    var status: Int32 = 0
    let foundPid = waitpid(-1, &status, WNOHANG)
    if let oldChild = children.removeValue(forKey: foundPid) {
      oldChild.cleanup()
    }
  }

  deinit {
    for child in children {
      child.value.cleanup()
    }
  }
}

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

  func run() throws -> EventLoopFuture<Void> {
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
