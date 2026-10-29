// PTYSession.swift
// Brim
//
// A real pseudo-terminal: openpty + posix_spawn (new session, the tty as controlling terminal).
// Nothing is ever written to the child except what the caller passes to `send`.

import Darwin
import Foundation

enum PTYError: Error, LocalizedError {
  case openFailed(Int32)
  case spawnFailed(Int32)

  var errorDescription: String? {
    switch self {
    case .openFailed(let code): "Couldn’t create a terminal (\(String(cString: strerror(code))))."
    case .spawnFailed(let code): "Couldn’t start the shell (\(String(cString: strerror(code))))."
    }
  }
}

final class PTYSession: @unchecked Sendable {
  /// Bytes read from the terminal. Called on an internal queue.
  var onOutput: (@Sendable (Data) -> Void)?
  /// Called once on an internal queue when the child exits.
  var onExit: (@Sendable (Int32) -> Void)?

  private(set) var pid: pid_t = 0
  private var master: Int32 = -1
  private let queue = DispatchQueue(label: "brim.pty")
  private var readSource: DispatchSourceRead?
  private var exitSource: DispatchSourceProcess?
  private let lock = NSLock()
  private var closed = false

  var isRunning: Bool {
    lock.lock(); defer { lock.unlock() }
    return !closed && pid > 0
  }

  /// The user's login shell from the account database, never a guessed path.
  static func loginShell() -> String {
    if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
      let path = String(cString: shell)
      if FileManager.default.isExecutableFile(atPath: path) { return path }
    }
    if let env = ProcessInfo.processInfo.environment["SHELL"],
      FileManager.default.isExecutableFile(atPath: env) { return env }
    return "/bin/zsh"
  }

  static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
    var env = base
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    env["TERM_PROGRAM"] = "Brim"
    env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
    return env
  }

  /// Spawns `executable`. `login` makes a shell a login shell (`-l`).
  func start(
    executable: String = PTYSession.loginShell(), arguments: [String] = [], login: Bool = true,
    cwd: String = NSHomeDirectory(), columns: UInt16 = 80, rows: UInt16 = 12,
    environment: [String: String] = PTYSession.environment()
  ) throws {
    var win = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
    var masterFD: Int32 = -1
    var slaveFD: Int32 = -1
    guard openpty(&masterFD, &slaveFD, nil, nil, &win) == 0 else { throw PTYError.openFailed(errno) }
    _ = fcntl(masterFD, F_SETFD, FD_CLOEXEC)
    _ = fcntl(slaveFD, F_SETFD, FD_CLOEXEC)
    guard let namePointer = ttyname(slaveFD) else {
      close(masterFD); close(slaveFD)
      throw PTYError.openFailed(errno)
    }
    let slaveName = String(cString: namePointer)

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    // With POSIX_SPAWN_SETSID, opening the tty makes it the controlling terminal.
    posix_spawn_file_actions_addopen(&actions, 0, slaveName, O_RDWR, 0)
    posix_spawn_file_actions_adddup2(&actions, 0, 1)
    posix_spawn_file_actions_adddup2(&actions, 0, 2)
    posix_spawn_file_actions_addchdir_np(&actions, cwd)

    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
    var defaults = sigset_t(); sigfillset(&defaults)
    var none = sigset_t(); sigemptyset(&none)
    posix_spawnattr_setsigdefault(&attributes, &defaults)
    posix_spawnattr_setsigmask(&attributes, &none)

    let name = (executable as NSString).lastPathComponent
    let argv = [login ? "-" + name : name] + arguments
    var childPID: pid_t = 0
    let status = Self.withCStrings(argv) { argvPointer in
      Self.withCStrings(environment.map { "\($0.key)=\($0.value)" }) { envPointer in
        posix_spawn(&childPID, executable, &actions, &attributes, argvPointer, envPointer)
      }
    }
    close(slaveFD)
    guard status == 0 else {
      close(masterFD)
      throw PTYError.spawnFailed(status)
    }
    lock.lock()
    // A shell that exited on its own leaves its descriptor behind and the session marked closed;
    // restarting the tab must reopen it, or every keystroke after `exit` is dropped.
    let stale = closed ? master : -1
    master = masterFD
    pid = childPID
    closed = false
    lock.unlock()
    if stale >= 0 {
      readSource?.cancel()
      exitSource?.cancel()
      close(stale)
    }
    beginReading(masterFD)
    watchExit(childPID)
  }

  func send(_ data: Data) {
    lock.lock(); let fd = closed ? -1 : master; lock.unlock()
    guard fd >= 0, !data.isEmpty else { return }
    queue.async {
      data.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
          let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
          if written > 0 { offset += written } else if errno == EAGAIN || errno == EINTR { usleep(1000) } else { break }
        }
      }
    }
  }

  func send(_ text: String) { send(Data(text.utf8)) }

  func resize(columns: UInt16, rows: UInt16) {
    lock.lock(); let fd = closed ? -1 : master; let child = pid; lock.unlock()
    guard fd >= 0 else { return }
    var win = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
    _ = ioctl(fd, TIOCSWINSZ, &win)
    if child > 0 { kill(child, SIGWINCH) }
  }

  /// True when the tty is echoing typed characters (false at password prompts).
  var isEchoing: Bool {
    lock.lock(); let fd = closed ? -1 : master; lock.unlock()
    guard fd >= 0 else { return false }
    var term = termios()
    return tcgetattr(fd, &term) == 0 && (term.c_lflag & tcflag_t(ECHO)) != 0
  }

  /// The shell's current working directory, read from the kernel.
  var currentDirectory: String? {
    lock.lock(); let child = pid; lock.unlock()
    guard child > 0 else { return nil }
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
    guard proc_pidinfo(child, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
    return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
      $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
    }
  }

  func terminate() {
    lock.lock()
    guard !closed else { lock.unlock(); return }
    closed = true
    let child = pid
    let fd = master
    master = -1
    lock.unlock()
    readSource?.cancel()
    exitSource?.cancel()
    if child > 0 { kill(child, SIGHUP) }
    if fd >= 0 { close(fd) }
    if child > 0 { DispatchQueue.global().async { var s: Int32 = 0; waitpid(child, &s, 0) } }
  }

  deinit { terminate() }

  // MARK: Internals

  private func beginReading(_ fd: Int32) {
    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
    source.setEventHandler { [weak self] in
      var buffer = [UInt8](repeating: 0, count: 16 * 1024)
      let count = read(fd, &buffer, buffer.count)
      if count > 0 { self?.onOutput?(Data(buffer[0..<count])) } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
        source.cancel()
      }
    }
    source.resume()
    readSource = source
  }

  private func watchExit(_ child: pid_t) {
    let source = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: queue)
    source.setEventHandler { [weak self] in
      var status: Int32 = 0
      waitpid(child, &status, WNOHANG)
      self?.lock.lock()
      let wasClosed = self?.closed ?? true
      self?.closed = true
      self?.lock.unlock()
      if !wasClosed { self?.onExit?(status) }
      source.cancel()
    }
    source.resume()
    exitSource = source
  }

  private static func withCStrings<R>(
    _ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> R
  ) -> R {
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    pointers.append(nil)
    defer { pointers.forEach { free($0) } }
    return body(pointers)
  }
}
