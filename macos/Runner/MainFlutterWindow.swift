import Cocoa
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    AppyNative.shared.attach(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

/// Appy's native helpers: dropping folders onto the menu bar icon, notifications.
final class AppyNative: NSObject, UNUserNotificationCenterDelegate {
  static let shared = AppyNative()
  private var channel: FlutterMethodChannel?

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "appy/native", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "enableTrayDrop":
        result(AppyNative.shared.enableTrayDrop())
      case "notify":
        let args = call.arguments as? [String: Any] ?? [:]
        AppyNative.shared.notify(
          title: args["title"] as? String ?? "Appy",
          body: args["body"] as? String ?? "",
          sound: args["sound"] as? Bool ?? false
        )
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  /// Shows a macOS notification. macOS asks for permission the first time.
  private func notify(title: String, body: String, sound: Bool) {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      if sound { content.sound = .default }
      center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
  }

  // Show banners even while Appy is the active app.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  fileprivate func deliver(_ paths: [String]) {
    channel?.invokeMethod("trayDrop", arguments: paths)
  }

  private func enableTrayDrop() -> Bool {
    for window in NSApp.windows {
      guard let root = window.contentView, let button = findStatusButton(in: root) else { continue }
      // The button and everything inside it (tray_manager's click view) accept folders.
      var views: [NSView] = [button]
      var index = 0
      while index < views.count {
        views.append(contentsOf: views[index].subviews)
        index += 1
      }
      for view in views {
        AppyDropInstaller.install(on: view)
        view.registerForDraggedTypes([.fileURL])
      }
      return true
    }
    return false
  }

  private func findStatusButton(in view: NSView) -> NSStatusBarButton? {
    if let button = view as? NSStatusBarButton { return button }
    for sub in view.subviews {
      if let button = findStatusButton(in: sub) { return button }
    }
    return nil
  }

  static func folderPaths(_ info: NSDraggingInfo) -> [String] {
    let urls = info.draggingPasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] ?? []
    return urls.filter { url in
      var isDir: ObjCBool = false
      return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }.map { $0.path }
  }

  static func highlight(_ view: NSView, _ on: Bool) {
    var current: NSView? = view
    while let v = current {
      if let button = v as? NSStatusBarButton {
        button.highlight(on)
        return
      }
      current = v.superview
    }
  }
}

/// Adds drag-and-drop handling to an existing view instance by giving it a
/// small runtime subclass (the same trick KVO uses), so tray_manager itself
/// stays untouched.
enum AppyDropInstaller {
  static func install(on view: NSView) {
    guard let base: AnyClass = object_getClass(view) else { return }
    let baseName = NSStringFromClass(base)
    if baseName.hasPrefix("AppyDrop_") { return }
    let name = "AppyDrop_" + baseName.replacingOccurrences(of: ".", with: "_")

    var subclass: AnyClass? = NSClassFromString(name)
    if subclass == nil {
      guard let created = objc_allocateClassPair(base, name, 0) else { return }

      let entered: @convention(block) (NSView, NSDraggingInfo) -> NSDragOperation = { view, info in
        if AppyNative.folderPaths(info).isEmpty { return [] }
        AppyNative.highlight(view, true)
        return .copy
      }
      let updated: @convention(block) (NSView, NSDraggingInfo) -> NSDragOperation = { _, info in
        AppyNative.folderPaths(info).isEmpty ? [] : .copy
      }
      let exited: @convention(block) (NSView, NSDraggingInfo?) -> Void = { view, _ in
        AppyNative.highlight(view, false)
      }
      let prepare: @convention(block) (NSView, NSDraggingInfo) -> Bool = { _, _ in true }
      let perform: @convention(block) (NSView, NSDraggingInfo) -> Bool = { view, info in
        AppyNative.highlight(view, false)
        let paths = AppyNative.folderPaths(info)
        if paths.isEmpty { return false }
        AppyNative.shared.deliver(paths)
        return true
      }

      class_addMethod(created, NSSelectorFromString("draggingEntered:"), imp_implementationWithBlock(entered), "Q@:@")
      class_addMethod(created, NSSelectorFromString("draggingUpdated:"), imp_implementationWithBlock(updated), "Q@:@")
      class_addMethod(created, NSSelectorFromString("draggingExited:"), imp_implementationWithBlock(exited), "v@:@")
      class_addMethod(created, NSSelectorFromString("prepareForDragOperation:"), imp_implementationWithBlock(prepare), "B@:@")
      class_addMethod(created, NSSelectorFromString("performDragOperation:"), imp_implementationWithBlock(perform), "B@:@")
      objc_registerClassPair(created)
      subclass = created
    }
    if let subclass = subclass {
      object_setClass(view, subclass)
    }
  }
}
