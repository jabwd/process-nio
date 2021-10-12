import NIO
import Foundation
import ProcessNIO
#if os(Linux) 
import Glibc
#else
import Darwin
#endif

let ffArgs = [
  "-hide_banner",
  "-y",
  "-i",
  "stmary.mp4",
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

var bla2 = try spawn("/usr/local/bin/ffmpeg", args: ffArgs)
var status: Int32 = 0
waitpid(bla2, &status, 0)
print("FFmpeg status: \(status)")

var actions_t: posix_spawn_file_actions_t?
posix_spawn_file_actions_init(&actions_t)

let pipe = Pipe()
let handle = pipe.fileHandleForWriting

// posix_spawn_file_actions_adddup2(&actions_t, 2, handle.fileDescriptor)
// posix_spawn_file_actions_adddup2(&actions_t, 1, handle.fileDescriptor)

let unsafeArgs = ffArgs.map { $0.withCString(strdup) } + [nil]

// args2.append("/usr/bin/ffmpeg".cString(using: .utf8))
var pid: pid_t = 0
let rc = posix_spawn(&pid, "/usr/bin/ffmpeg", &actions_t, nil, unsafeArgs, [nil])
print("rc: \(rc)")
print("pid: \(pid)")
waitpid(pid, nil, 0)

posix_spawn_file_actions_destroy(&actions_t)
print("Work done.")

let bla = pipe.fileHandleForReading

print("Bloop: \(bla.readData(ofLength: 5)))")

exit(0)

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
defer { try! eventLoopGroup.syncShutdownGracefully() }
let q = DispatchQueue(label: "ffmpeg")

let threadPool = NIOThreadPool(numberOfThreads: 1)
threadPool.start()
let fileIO = NonBlockingFileIO(threadPool: threadPool)

let eventLoop = eventLoopGroup.next()

guard let ffmpegURL = ChildProcess.findURLFor(name: "ffmpeg") else {
  fatalError("Unable to find FFmpeg")
}

print("FFmpeg at: \(ffmpegURL)")
let child = ChildProcess.init(executableURL: ffmpegURL)

let args = [
  "-hide_banner",
  "-y",
  "-i",
  "stmary.mp4",
  "-c:v",
  "copy",
  "-c:a",
  "aac",
  "-b:a",
  "256k",
  "-f",
  "mp4",
  "output.mp4"
]

var nextLine: String = ""
func checkLine() -> String? {
  print("Checkline: \(nextLine)")
  if nextLine.contains("\n") || nextLine.contains("\r") {
    let lines = nextLine.split(separator: "\n")
    if lines.count == 0 {
      let lines2 = nextLine.split(separator: "\r")
      guard lines2.count > 0 else {
        return nil
      }
      let line2 = String(lines2.first!)
      if (line2.count + 1) > nextLine.count {
        nextLine = ""
      } else {
        nextLine.removeFirst(line2.count + 1)
      }
      return line2
    }
    let line = String(lines.first!)
    if (line.count + 1) > nextLine.count { 
      nextLine = ""
    } else {
      nextLine.removeFirst(line.count + 1)
    }
    return line
  } else {
    return nil
  }
}

func timecodeToSeconds(_ timecode: String) -> Double? {
  let components = timecode.split(separator: ":")
  guard components.count == 3 else {
    return nil
  }
  let hours = parseDigit(components[0])
  let minutes = parseDigit(components[1])
  let seconds = parseDigit(components[2])
  return (hours * 3600) + (minutes * 60) + seconds
}

guard let duration = timecodeToSeconds("00:03:37.54") else {
  fatalError("Unable to determine duration of file")
}
print("Duration: \(duration)s")

func parseDigit(_ digit: Substring) -> Double {
  guard digit.count >= 2 else {
    return 0.0
  }
  if digit[digit.startIndex] == "0" {
    return Double(String(digit[digit.index(digit.startIndex, offsetBy: 1)])) ?? 0.0
  }
  return Double(String(digit)) ?? 0.0
}

let result = try child.run(withArguments: args, fileIO: fileIO, on: eventLoop) { output in
  guard let output = output else {
    return
  }
  nextLine += output
  while nextLine.contains("\n") || nextLine.contains("\r") {
    guard let line = checkLine() else {
      return
    }
    if let range = line.range(of: "time") {
      let timeStart = line[range.lowerBound...]
      let timeEnd = timeStart.firstIndex(of: " ")!
      let startIdx = timeStart.index(timeStart.startIndex, offsetBy: 5)
      let timeCode = timeStart[startIdx..<timeEnd]
      guard let seconds = timecodeToSeconds(String(timeCode)) else {
        continue
      }
      let percentage = floor(seconds / duration * 1000) / 10
      print("Encoding: \(percentage)%")
    }
  }
}.always { result in 
  switch result {
  case .success():
    print("Process is done")
    break
  case .failure(let error):
    print("Execute failed: \(error)")
    break
  }
}

print("Awaiting result");
try result.wait()
