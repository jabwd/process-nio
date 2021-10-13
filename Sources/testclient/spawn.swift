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

enum POSIXError: Error {
  case nonZeroStatus(Int32)
}

public typealias ProcessOutputHandler = (String) -> Void
public typealias ProcessFinishedHandler = () -> Void

public final class ProcessChannelHandler: ChannelInboundHandler {
  public typealias InboundIn = ByteBuffer
  public var outputHandler: ProcessOutputHandler?
  public var processFinishedHandler: ProcessFinishedHandler?

  init(outputHandler: ProcessOutputHandler? = nil, finishedHandler: ProcessFinishedHandler? = nil) {
    self.outputHandler = outputHandler
    self.processFinishedHandler = finishedHandler
  }

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let inboundData = self.unwrapInboundIn(data)

    guard let str = String(bytes: inboundData.readableBytesView, encoding: .utf8) else {
      return
    }
    outputHandler?(str)
  }

  public func channelInactive(context: ChannelHandlerContext) {
    processFinishedHandler?()
  }
}



public enum ProcessNIOError: Error {
  case spawnFailed(Int32)
}

public final class ProcessManager {
  private var children: [Int32: ProcessNIO] = [:]
  var oldSignalHandlers: [sigaction] = []

  static let shared = ProcessManager()

  init() {
    var action = sigaction()
    let handler: SigactionHandler = { (signo, info, context) in
      var info = info
      ProcessManager.shared.handleSignal(signo, action: &info, context: context)
    }
    action.__sigaction_handler = unsafeBitCast(handler, to: sigaction.__Unnamed_union___sigaction_handler.self)
    var oldAction = sigaction()
    sigaction(SIGCHLD, &action, &oldAction)
    oldSignalHandlers.append(oldAction)
  }

  func launch(
    path: String,
    args: [String],
    eventLoopGroup: EventLoopGroup,
    onRead readHandler: ProcessOutputHandler? = nil,
    onFinished finishedHandler: ProcessFinishedHandler? = nil
    ) throws -> ProcessNIO {
    let process = try ProcessNIO(path: path, args: args, eventLoopGroup: eventLoopGroup, onRead: readHandler, onFinished: finishedHandler)
    self.children[process.pid] = process
    return process
  }

  func handleSignal(_ signo: Int32, action: inout sigaction, context: UnsafeMutableRawPointer?) {
    for oldHandler in oldSignalHandlers {
      let oldAction = oldHandler
      let oldHandler = unsafeBitCast(oldAction.__sigaction_handler, to: SigactionHandler.self)
      oldHandler(signo, oldAction, nil)
    }
    closeFinishedChildren()
  }

  func closeFinishedChildren() {
    for (pid, process) in children {
      var status: Int32 = -1
      waitpid(pid, &status, WNOHANG)
      if (status != 0) {
        print("Cleaning up process")
        process.cleanup()
      }
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
  public let pid: Int32
  private let readDescriptor: Int32
  private let writeDescriptor: Int32

  public static func findPathFor(name: String) -> String? {
    return nil
  }

  public init(
    path: String,
    args: [String],
    eventLoopGroup: EventLoopGroup,
    onRead readHandler: ProcessOutputHandler? = nil,
    onFinished finishedHandler: ProcessFinishedHandler? = nil
  ) throws {
    var fileDescriptors: [Int32] = [Int32](repeating: 0, count: 2)
    pipe(&fileDescriptors)
    readDescriptor = fileDescriptors[0]
    writeDescriptor = fileDescriptors[1]

    channel = try NIOPipeBootstrap(group: eventLoopGroup)
      .channelOption(ChannelOptions.maxMessagesPerRead, value: 1)
      .channelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
      .channelInitializer({ channel in
        channel.pipeline.addHandler(ProcessChannelHandler(outputHandler: readHandler, finishedHandler: finishedHandler))
      })
      .withPipes(inputDescriptor: readDescriptor, outputDescriptor: writeDescriptor).wait()

    #if os(Linux)
    var fileActions = posix_spawn_file_actions_t()
    #else
    var fileActions: posix_spawn_file_actions_t?
    #endif
    posix_spawn_file_actions_init(&fileActions)
    defer { posix_spawn_file_actions_destroy(&fileActions) }
    posix_spawn_file_actions_adddup2(&fileActions, writeDescriptor, STDERR_FILENO)
    posix_spawn_file_actions_adddup2(&fileActions, writeDescriptor, STDOUT_FILENO)

    let completedArgs = [path] + args
    let unsafeArgs = completedArgs.map { $0.withCString(strdup) } + [nil]
    var newPid: Int32 = -1
    let rc = posix_spawn(&newPid, path, &fileActions, nil, unsafeArgs, nil)
    guard rc == 0 else {
      let err = strerror(rc)
      let str = String(cString: err!)
      print("str: \(str)")
      throw ProcessNIOError.spawnFailed(rc)
    }

    pid = newPid
  }

  func cleanup() {
    _ = channel.close().always { [weak self] _ in
      guard let self = self else {
        return
      }
      close(self.readDescriptor)
      close(self.writeDescriptor)
    }
  }
}
