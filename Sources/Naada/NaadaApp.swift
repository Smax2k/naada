import AppKit
import SwiftUI

@main
struct NaadaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Naada") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: RecorderViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isBusy else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Un enregistrement est en cours"
        alert.informativeText = "Arrêtez l'enregistrement avant de quitter Naada, pour ne pas perdre la fin du fichier MP3."
        alert.addButton(withTitle: "Revenir à Naada")
        alert.runModal()
        return .terminateCancel
    }
}
