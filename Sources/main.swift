import AppKit
import SwiftUI
import IOKit

final class HelperModel: ObservableObject {
    @Published var autoDetect: Bool { didSet { UserDefaults.standard.set(autoDetect, forKey: "autoDetect"); preferencesChanged?() } }
    @Published var showMenuBar: Bool { didSet { UserDefaults.standard.set(showMenuBar, forKey: "showMenuBar"); preferencesChanged?() } }
    @Published var swapFaces: Bool { didSet { UserDefaults.standard.set(swapFaces, forKey: "swapFaces") } }
    @Published var controllers: [ControllerDevice] = []
    @Published var steam: SteamState = .closed
    @Published var busy = false
    @Published var ready = false
    var preferencesChanged: (() -> Void)?
    var launch: (() -> Void)?
    var hide: (() -> Void)?
    var quit: (() -> Void)?

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["autoDetect": false, "showMenuBar": true, "swapFaces": true])
        autoDetect = defaults.bool(forKey: "autoDetect")
        showMenuBar = defaults.bool(forKey: "showMenuBar")
        swapFaces = defaults.bool(forKey: "swapFaces")
    }
    var controllerLabel: String {
        guard ready else { return "Checking controllers…" }
        guard !controllers.isEmpty else { return "No controller detected" }
        if controllers.count == 1 { return controllers[0].name }
        return "\(controllers.count) matching controllers connected"
    }
    var launchTitle: String {
        if busy { return "Starting Steam…" }
        return steam.pid == nil ? "Open Steam" : "Restart Steam"
    }
}

struct SettingsView: View {
    @ObservedObject var model: HelperModel

    private func status(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                status(model.controllerLabel, model.controllers.isEmpty ? .gray : .green)
                status(model.ready ? model.steam.label : "Checking Steam…",
                       { if case .fixed = model.steam { return Color.green }; return model.steam.pid == nil ? Color.gray : Color.orange }())
            }.padding(16).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(12)

            VStack(alignment: .leading, spacing: 16) {
                Toggle("Auto-detect controllers", isOn: $model.autoDetect)
                Toggle("Show menu bar icon", isOn: $model.showMenuBar)
                Toggle("Swap A/B and X/Y", isOn: $model.swapFaces)
            }.toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 8) {
                Button(action: { model.launch?() }) {
                    HStack {
                        if model.busy { ProgressView().controlSize(.small) }
                        Text(model.launchTitle).frame(maxWidth: .infinity)
                    }.padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy || !model.ready)
            }

            Divider()
            HStack {
                Spacer()
                Button("Hide") { model.hide?() }
                Button("Quit") { model.quit?() }.disabled(model.busy)
            }
        }.padding(20).frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

final class HelperDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = HelperModel()
    private let queue = DispatchQueue(label: "XboxHelper.monitor", qos: .utility)
    private var window: NSWindow!
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var polling = false
    private var refreshAgain = false
    private var promptShowing = false
    private var policy = PromptPolicy()
    private var enabledBefore = false
    private var pollNumber = 0
    private var notificationPort: IONotificationPortRef?
    private var arrivalIterator: io_iterator_t = 0
    private var removalIterator: io_iterator_t = 0
    private let smokeTest = CommandLine.arguments.contains("--smoke-test")
    private let shim = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/xbox-identity.dylib")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        model.preferencesChanged = { [weak self] in self?.preferencesChanged() }
        model.launch = { [weak self] in self?.launchSteam() }
        model.hide = { [weak self] in self?.hideSettings() }
        model.quit = { NSApp.terminate(nil) }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 310),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Xbox Controller Helper"
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.center()
        enabledBefore = model.autoDetect
        preferencesChanged()
        showSettings()
        observeControllerConnections()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        if smokeTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                print("Window created; menu bar configured; monitoring completed without launching Steam")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.busy else { return .terminateNow }
        showSettings()
        NSSound.beep()
        return .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideSettings()
        return false
    }

    private func preferencesChanged() {
        if model.autoDetect != enabledBefore {
            policy.reset()
            if model.autoDetect && !model.showMenuBar { model.showMenuBar = true }
            enabledBefore = model.autoDetect
        }
        if model.showMenuBar && statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem?.button?.image = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "Xbox Controller Helper")
            statusItem?.button?.image?.isTemplate = true
        } else if !model.showMenuBar, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        updateMenu()
        if window != nil, !window.isVisible {
            NSApp.setActivationPolicy(model.showMenuBar ? .accessory : .regular)
        }
    }

    private func updateMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        func label(_ text: String) {
            let row = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            row.isEnabled = false
            menu.addItem(row)
        }
        func action(_ title: String, _ selector: Selector, enabled: Bool = true) {
            let row = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            row.target = self
            row.isEnabled = enabled
            menu.addItem(row)
        }
        label(model.controllerLabel)
        label(model.ready ? model.steam.label : "Checking Steam…")
        menu.addItem(.separator())
        action("Open Settings…", #selector(openSettings))
        action(model.launchTitle, #selector(runSteam), enabled: model.ready && !model.busy)
        let auto = NSMenuItem(title: "Automatic Detection", action: #selector(toggleDetection), keyEquivalent: "")
        auto.target = self
        auto.state = model.autoDetect ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())
        action("Quit Helper", #selector(quitHelper), enabled: !model.busy)
        item.menu = menu
        item.button?.toolTip = "Xbox Controller Helper · \(model.steam.label)"
    }

    @objc private func openSettings() { showSettings() }
    @objc private func runSteam() { launchSteam() }
    @objc private func toggleDetection() { model.autoDetect.toggle() }
    @objc private func quitHelper() { NSApp.terminate(nil) }

    private func showSettings() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideSettings() {
        window.orderOut(nil)
        NSApp.setActivationPolicy(model.showMenuBar ? .accessory : .regular)
        // With no menu bar icon, the Dock icon remains available to reopen.
    }

    private func refresh() {
        guard !polling else { refreshAgain = true; return }
        polling = true
        pollNumber += 1
        let previous = model.steam
        let inspectLibraries = pollNumber % 4 == 0
        queue.async { [weak self] in
            let controllers = HostEnvironment.controllers()
            let pid = HostEnvironment.steamPID()
            let steam: SteamState
            if let pid {
                steam = pid == previous.pid && !inspectLibraries ? previous : HostEnvironment.steamState(pid: pid)
            } else { steam = .closed }
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                self.model.controllers = controllers
                self.model.steam = steam
                self.model.ready = true
                self.updateMenu()
                self.considerPrompt()
                if self.refreshAgain { self.refreshAgain = false; self.refresh() }
            }
        }
    }

    private func considerPrompt() {
        guard !smokeTest,
              policy.offer(enabled: model.autoDetect, controllerIDs: model.controllers.map(\.id),
                           busy: model.busy || promptShowing, needsFix: model.steam.needsFix) else { return }
        promptShowing = true
        // Defer presentation so the monitor callback can finish first.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.promptShowing = false }
            guard self.model.autoDetect, !self.model.busy,
                  !self.model.controllers.isEmpty, self.model.steam.needsFix else { return }
            let restarting = self.model.steam.pid != nil
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.messageText = restarting ? "Restart Steam with the Xbox fix?" : "Open Steam with the Xbox fix?"
            alert.informativeText = "Controller detected."
            alert.addButton(withTitle: restarting ? "Restart Steam" : "Open Steam")
            alert.addButton(withTitle: "Not Now")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { self.launchSteam() }
        }
    }

    private func launchSteam() {
        guard !model.busy else { return }
        model.busy = true
        updateMenu()
        let swap = model.swapFaces
        let shim = self.shim
        queue.async { [weak self] in
            let result = Result { try HostEnvironment.restartAndStart(shim: shim, swap: swap) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.model.busy = false
                switch result {
                case .success: break
                case .failure(let error):
                    let alert = NSAlert()
                    alert.icon = NSApp.applicationIconImage
                    alert.messageText = "Steam couldn’t start with the fix"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
                self.pollNumber = 3 // Inspect the newly launched process immediately.
                self.refresh()
                self.updateMenu()
            }
        }
    }

    private func observeControllerConnections() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            while true {
                let service = IOIteratorNext(iterator)
                guard service != 0 else { break }
                IOObjectRelease(service)
            }
            guard let context else { return }
            Unmanaged<HelperDelegate>.fromOpaque(context).takeUnretainedValue().refresh()
        }
        // Register both arrival and removal notifications. Drain each initial
        // iterator to arm it; the regular refresh provides a fallback as well.
        for kind in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            if IOServiceAddMatchingNotification(port, kind, IOServiceMatching("IOHIDDevice"), callback, context, &iterator) == KERN_SUCCESS {
                while true {
                    let service = IOIteratorNext(iterator)
                    guard service != 0 else { break }
                    IOObjectRelease(service)
                }
                if kind == kIOFirstMatchNotification { arrivalIterator = iterator }
                else { removalIterator = iterator }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if arrivalIterator != 0 { IOObjectRelease(arrivalIterator) }
        if removalIterator != 0 { IOObjectRelease(removalIterator) }
        if let notificationPort { IONotificationPortDestroy(notificationPort) }
    }
}

if CommandLine.arguments.contains("--dry-run") {
    let devices = HostEnvironment.controllers()
    let state = HostEnvironment.steamPID().map(HostEnvironment.steamState) ?? .closed
    let shim = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/xbox-identity.dylib")
    print("Steam executable exists: \(FileManager.default.isExecutableFile(atPath: HostEnvironment.steamExecutable.path))")
    print("Identity library exists: \(FileManager.default.fileExists(atPath: shim.path))")
    print("Matching controllers: \(devices.count)")
    for device in devices { print("Controller: \(device.name)") }
    print(state.label)
    exit(0)
}

let app = NSApplication.shared
let delegate = HelperDelegate()
app.delegate = delegate
app.run()
