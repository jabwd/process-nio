import NIO
import Foundation
#if os(Linux) 
import Glibc
#else
import Darwin
#endif
import ProcessNIO

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

func parseDigit(_ digit: Substring) -> Double {
  guard digit.count >= 2 else {
    return 0.0
  }
  if digit[digit.startIndex] == "0" {
    return Double(String(digit[digit.index(digit.startIndex, offsetBy: 1)])) ?? 0.0
  }
  return Double(String(digit)) ?? 0.0
}

final class FFmpegProgressHandler {
  typealias ProgressCallback = (Double) -> Void

  private var outputBuffer: String = ""
  private let progressCallback: ProgressCallback
  private let durationInSeconds: Double

  init(durationInSeconds: Double, _ onProgress: @escaping ProgressCallback) {
    self.progressCallback = onProgress
    self.durationInSeconds = durationInSeconds
  }

  func onRead(_ output: [UInt8]) {
    outputBuffer += String(bytes: output, encoding: .utf8) ?? ""
    checkForLine()
  }

  private func nextLine() -> Substring? {
    let lines = outputBuffer.split(separator: "\n")
    if lines.count == 0 {
      return outputBuffer.split(separator: "\r").first
    }
    return lines.first
  }

  private func checkForLine() {
    guard outputBuffer.contains(where: { char in
      return char == "\n" || char == "\r"
    }) else {
      return
    }
    guard let line = nextLine() else {
      return
    }
    let lineCopy = String(line)
    if (lineCopy.count + 1) > outputBuffer.count {
      outputBuffer = ""
    } else {
      outputBuffer.removeFirst(lineCopy.count)
    }

    if let range = lineCopy.range(of: " time=") {
      let timeStart = lineCopy[range.upperBound...]
      let timeEnd = timeStart.firstIndex(of: " ")!
      let timeCode = timeStart[..<timeEnd]
      guard let seconds = timecodeToSeconds(String(timeCode)) else {
        return
      }
      let percentage = floor((seconds / durationInSeconds) * 1000) / 1000
      progressCallback(percentage)
    }
    checkForLine()
  }
}

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
  "/Users/jabwd/Desktop/input.mp4",
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
  "/Users/jabwd/Desktop/input.mp4",
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

let progress1Handler = FFmpegProgressHandler(durationInSeconds: 26.41) { progress in
  let percentage = progress * 100
  print("Encoding: \(percentage)%")
}
let process = ProcessNIO(
  .path("/opt/homebrew/bin/ffmpeg"),
  arguments: ffArgs,
  eventLoopGroup: eventLoopGroup
)

print("Going to run first")
let processFut = process.run(on: eventLoopGroup.next(), onRead: progress1Handler.onRead)
print("First is running")

let progress2Handler = FFmpegProgressHandler(durationInSeconds: 26.41) { progress in
  print("Encoding: \(progress*100)%")
}

let eventLoop = eventLoopGroup.next()
let process2 = ProcessNIO(
  .path("/opt/homebrew/bin/ffmpeg"),
  arguments: ffArgs2,
  eventLoopGroup: eventLoopGroup
).run(on: eventLoop, onRead: progress2Handler.onRead)
print("Second is running")

print("awaiting data now")
_ = try? process2.fold([processFut], with: { (status1, status2) -> EventLoopFuture<Int32> in
  print("Both processes done")
  return eventLoop.makeSucceededFuture(status1 + status2)
}).always { result in
  switch result {
  case .success(let status):
    print("Folded with: \(status)")
  case .failure(let error):
    print("Error: \(error)")
  }
}.wait()
