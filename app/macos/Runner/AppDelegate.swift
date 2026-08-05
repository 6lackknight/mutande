import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Menu-bar accessory: hide Dock icon (NSActivationPolicy.accessory).
    NSApp.setActivationPolicy(.accessory)
    // Show banners while mutande is frontmost (inbox-watch cold mail).
    UNUserNotificationCenter.current().delegate = self
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Stay alive for the status item when the window is closed/hidden.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(macOS 11.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }
}
