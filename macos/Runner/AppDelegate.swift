import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    guard !InstallationLocationValidator.isCurrentLocationAllowed else {
      return
    }

    NSApp.windows.forEach { $0.orderOut(nil) }
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    let language = Locale.preferredLanguages.first ?? "en"
    if language.hasPrefix("es") {
      alert.messageText = "Mueve la aplicación a Aplicaciones"
      alert.informativeText =
        "Kontakt Library Manager solo puede ejecutarse desde la carpeta /Applications. Abre el DMG, arrastra la aplicación a Applications y vuelve a abrirla desde allí."
      alert.addButton(withTitle: "Cerrar")
    } else if language.hasPrefix("pt") {
      alert.messageText = "Mova o aplicativo para Aplicativos"
      alert.informativeText =
        "O Kontakt Library Manager só pode ser executado a partir da pasta /Applications. Abra o DMG, arraste o aplicativo para Applications e abra-o novamente a partir dessa pasta."
      alert.addButton(withTitle: "Fechar")
    } else {
      alert.messageText = "Move the application to Applications"
      alert.informativeText =
        "Kontakt Library Manager can only run from /Applications. Open the DMG, drag the application to Applications, and reopen it from there."
      alert.addButton(withTitle: "Quit")
    }
    alert.alertStyle = .warning
    alert.runModal()
    NSApp.terminate(nil)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
