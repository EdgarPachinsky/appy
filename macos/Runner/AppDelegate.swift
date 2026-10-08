import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override init() {
    super.init()
    // Whatever way Appy quits (menu, Cmd+Q, Dock), stop the commands it started.
    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: nil
    ) { _ in
      AppDelegate.terminateChildProcesses()
    }
  }

  // Appy keeps living in the menu bar when its window is closed.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // Clicking the Dock icon brings the hidden window back.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows where window is MainFlutterWindow {
        window.makeKeyAndOrderFront(self)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  static func terminateChildProcesses() {
    var all: [Int32] = []
    var queue: [Int32] = [getpid()]
    while let pid = queue.popLast() {
      for child in childPids(of: pid) where !all.contains(child) {
        all.append(child)
        queue.append(child)
      }
    }
    for pid in all.reversed() {
      kill(pid, SIGTERM)
    }
  }

  private static func childPids(of pid: Int32) -> [Int32] {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-P", String(pid)]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do { try task.run() } catch { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    let text = String(data: data, encoding: .utf8) ?? ""
    return text.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
  }
}
