public enum ProcessNIOError: Error {
  case spawnFailed(Int32, reason: String?)
  case fileNotFound
}
