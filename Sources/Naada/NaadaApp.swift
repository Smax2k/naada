import AppKit
import SwiftUI

@main
struct NaadaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // La sonde sort ici, avant toute fenêtre, toute scène et toute
        // activation. Sans l'argument, elle ne fait rien.
        CaptureProbe.exitIfRequested(arguments: CommandLine.arguments)
    }

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
        alert.messageText = NSLocalizedString("A recording is in progress", comment: "Quit guard alert title")
        alert.informativeText = NSLocalizedString(
            "Stop the recording before quitting Naada so the end of the MP3 file is not lost.",
            comment: "Quit guard alert message"
        )
        alert.addButton(withTitle: NSLocalizedString("Return to Naada", comment: "Quit guard alert button"))
        alert.runModal()
        return .terminateCancel
    }
}
