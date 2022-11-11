public enum ProcessNIOError: Error {
  case spawnFailed(Int32, reason: String?)
  case fileNotFound
  case binaryNotFound
  case nonZeroExit(Int32)
}
