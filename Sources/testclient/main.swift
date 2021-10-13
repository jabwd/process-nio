import NIO
import Foundation
#if os(Linux) 
import Glibc
#else
import Darwin
#endif
import ProcessNIO

func trap(_ signum: Int32, action: @escaping SigactionHandler) {
  var sigAction = sigaction()
  #if os(Linux)
    sigAction.__sigaction_handler = unsafeBitCast(action, to: sigaction.__Unnamed_union___sigaction_handler.self)
    sigaction(signum, &sigAction, nil)
  #else
    sigAction.__sigaction_u = __sigaction_u.init(__sa_sigaction: action)
    sigaction(signum, &sigAction, nil)
  #endif
}

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
defer { try! eventLoopGroup.syncShutdownGracefully() }

let ffArgs = [
  "-hide_banner",
  "-y",
  "-i",
  "input.mp4",
  "-c:v",
  "libx264",
  "-movflags",
  "+faststart",
  "-pix_fmt",
  "yuv420p",
  "-preset",
  "veryfast",
  "-crf",
  "23",
  "-c:a",
  "aac",
  "-b:a",
  "256k",
  "-f",
  "mp4",
  "output.mp4"
]

let ffArgs2 = [
  "-hide_banner",
  "-y",
  "-i",
  "input.mp4",
  "-c:v",
  "libx264",
  "-movflags",
  "+faststart",
  "-pix_fmt",
  "yuv420p",
  "-preset",
  "veryfast",
  "-crf",
  "23",
  "-c:a",
  "aac",
  "-b:a",
  "256k",
  "-f",
  "mp4",
  "output2.mp4"
]

let process = try ProcessNIO(
  path: "/usr/bin/ffmpeg",
  args: ffArgs,
  eventLoopGroup: eventLoopGroup,
  onRead: { output in
    print("FF1: \(output)")
  }
)

print("Going to run first")
let processFut = try process.run()
print("First is running")

let process2 = try ProcessNIO(
  path: "/usr/bin/ffmpeg",
  args: ffArgs2,
  eventLoopGroup: eventLoopGroup,
  onRead: { output in
    print("FF2: \(output)")
  }
).run()
print("Second is running")

print("awaiting data now")
try process2.fold([processFut], with: { _, _ in
  print("Both processes done")
  return process.channel.eventLoop.makeSucceededVoidFuture()
}).wait()

print("Done")

//
//var nextLine: String = ""
//func checkLine() -> String? {
//  print("Checkline: \(nextLine)")
//  if nextLine.contains("\n") || nextLine.contains("\r") {
//    let lines = nextLine.split(separator: "\n")
//    if lines.count == 0 {
//      let lines2 = nextLine.split(separator: "\r")
//      guard lines2.count > 0 else {
//        return nil
//      }
//      let line2 = String(lines2.first!)
//      if (line2.count + 1) > nextLine.count {
//        nextLine = ""
//      } else {
//        nextLine.removeFirst(line2.count + 1)
//      }
//      return line2
//    }
//    let line = String(lines.first!)
//    if (line.count + 1) > nextLine.count { 
//      nextLine = ""
//    } else {
//      nextLine.removeFirst(line.count + 1)
//    }
//    return line
//  } else {
//    return nil
//  }
//}
//
//func timecodeToSeconds(_ timecode: String) -> Double? {
//  let components = timecode.split(separator: ":")
//  guard components.count == 3 else {
//    return nil
//  }
//  let hours = parseDigit(components[0])
//  let minutes = parseDigit(components[1])
//  let seconds = parseDigit(components[2])
//  return (hours * 3600) + (minutes * 60) + seconds
//}
//
//guard let duration = timecodeToSeconds("00:03:37.54") else {
//  fatalError("Unable to determine duration of file")
//}
//print("Duration: \(duration)s")
//
//func parseDigit(_ digit: Substring) -> Double {
//  guard digit.count >= 2 else {
//    return 0.0
//  }
//  if digit[digit.startIndex] == "0" {
//    return Double(String(digit[digit.index(digit.startIndex, offsetBy: 1)])) ?? 0.0
//  }
//  return Double(String(digit)) ?? 0.0
//}
//
//let result = try child.run(withArguments: args, fileIO: fileIO, on: eventLoop) { output in
//  guard let output = output else {
//    return
//  }
//  nextLine += output
//  while nextLine.contains("\n") || nextLine.contains("\r") {
//    guard let line = checkLine() else {
//      return
//    }
//    if let range = line.range(of: "time") {
//      let timeStart = line[range.lowerBound...]
//      let timeEnd = timeStart.firstIndex(of: " ")!
//      let startIdx = timeStart.index(timeStart.startIndex, offsetBy: 5)
//      let timeCode = timeStart[startIdx..<timeEnd]
//      guard let seconds = timecodeToSeconds(String(timeCode)) else {
//        continue
//      }
//      let percentage = floor(seconds / duration * 1000) / 10
//      print("Encoding: \(percentage)%")
//    }
//  }
//}.always { result in 
//  switch result {
//  case .success():
//    print("Process is done")
//    break
//  case .failure(let error):
//    print("Execute failed: \(error)")
//    break
//  }
//}
//
//print("Awaiting result");
//try result.wait()
