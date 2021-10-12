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

enum POSIXError: Error {
  case nonZeroStatus(Int32)
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
  print("str: \(str)")
  exit(0)
  return pid
}
