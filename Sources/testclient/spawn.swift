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

public final class ProcessChannelHandler: ChannelInboundHandler {
  public typealias InboundIn = ByteBuffer

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let inboundData = self.unwrapInboundIn(data)

    let str = String(bytes: inboundData.readableBytesView, encoding: .utf8) ?? "Read failed"
    print("Channel read: \(str)")
  }

  public func channelInactive(context: ChannelHandlerContext) {
    print("Channel inactive")
  }
}

public enum ProcessNIOError: Error {
  case spawnFailed(Int32)
}

public final class ProcessNIO {
  public let channel: Channel
  public let pid: Int32

  public static func findPathFor(name: String) -> String? {
    return nil
  }

  public init(path: String, args: [String], eventLoopGroup: EventLoopGroup) throws {
    var fileDescriptors: [Int32] = [Int32](repeating: 0, count: 2)
    pipe(&fileDescriptors)
    let readDescriptor = fileDescriptors[0]
    let writeDescriptor = fileDescriptors[1]

    channel = try NIOPipeBootstrap(group: eventLoopGroup)
      .channelOption(ChannelOptions.maxMessagesPerRead, value: 1)
      .channelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
      .channelInitializer({ channel in
        channel.pipeline.addHandler(ProcessChannelHandler())
      })
      .withPipes(inputDescriptor: readDescriptor, outputDescriptor: writeDescriptor).wait()

    var fileActions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&fileActions)
    posix_spawn_file_actions_adddup2(&fileActions, writeDescriptor, STDERR_FILENO)
    posix_spawn_file_actions_adddup2(&fileActions, writeDescriptor, STDOUT_FILENO)

    let completedArgs = [path] + args
    let unsafeArgs = completedArgs.map { $0.withCString(strdup) } + [nil]
    var newPid: Int32 = -1
    let rc = posix_spawn(&newPid, path, &fileActions, nil, unsafeArgs, nil)
    guard rc == 0 else {
      throw ProcessNIOError.spawnFailed(rc)
    }
    posix_spawn_file_actions_destroy(&fileActions)
    fileActions = nil

    pid = newPid
  }
}

func spawn(_ path: String, args: [String]) throws -> Int32 {
  var bla: [Int32] = [Int32](repeating: 0, count: 2)
  Darwin.pipe(&bla)

  var actions_t: posix_spawn_file_actions_t?
  posix_spawn_file_actions_init(&actions_t)
  posix_spawn_file_actions_adddup2(&actions_t, bla[1], STDERR_FILENO)
  posix_spawn_file_actions_adddup2(&actions_t, bla[1], STDOUT_FILENO)

  let completeArgs = [path] + args
  let unsafeArgs = completeArgs.map { $0.withCString(strdup) } + [nil]
  var pid: Int32 = -1
  let rc = posix_spawn(&pid, path, &actions_t, nil, unsafeArgs, nil)
  posix_spawn_file_actions_destroy(&actions_t)
  guard rc == 0 else {
    throw POSIXError.nonZeroStatus(rc)
  }
  var status: Int32 = -1
  waitpid(pid, &status, 0)
  print("RC: \(rc) \(status)")
  var bytes: [UInt8] = [UInt8](repeating: 0, count: 2048)
  read(bla[0], &bytes, bytes.count)
  let str = String(bytes: bytes, encoding: .utf8)
  print("str: \(String(describing: str))")
  return pid
}
