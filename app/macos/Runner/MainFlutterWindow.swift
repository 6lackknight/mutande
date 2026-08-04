import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Match welcome splash so Keychain wait never flashes an empty black void.
    let splash = NSColor(calibratedRed: 12 / 255, green: 10 / 255, blue: 9 / 255, alpha: 1)
    self.backgroundColor = splash
    flutterViewController.backgroundColor = splash

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
