import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = NSRect(x: self.frame.origin.x, y: self.frame.origin.y, width: 1240, height: 780)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 780, height: 620)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    KontaktSystemBridge.register(with: flutterViewController)

    super.awakeFromNib()
  }
}
