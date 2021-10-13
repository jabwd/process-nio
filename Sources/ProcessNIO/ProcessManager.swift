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
    var oldAction: sigaction? = sigaction()
    sigaction(SIGCHLD, &action, &oldAction!)
    if let oldActionUnwrapped = oldAction {
      oldSignalHandlers.append(oldActionUnwrapped)
    }
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
      guard let oldHandler = oldAction.__sigaction_handler.sa_sigaction else {
        continue
      }
      #else
      if oldAction.__sigaction_u.__sa_handler == nil && oldAction.__sigaction_u.__sa_sigaction == nil {
        continue
      }
      let oldHandler = oldAction.__sigaction_u.__sa_sigaction
      #endif
      oldHandler(signo, info, context)
    }

    // Multiple children can have all exited in the same signal
    var status: Int32 = 0
    var pid: Int32 = 0
    repeat {
      pid = waitpid(-1, &status, WNOHANG)
      if pid < 0 {
        break
      }
      let terminationStatus = (status & 0xFF00) >> 8
      if let oldChild = children.removeValue(forKey: pid) {
        oldChild.terminationStatus = terminationStatus
        oldChild.cleanup()
      }
    } while pid > 0
  }

  deinit {
    for child in children {
      child.value.cleanup()
    }
  }
}
