// Lid Agents — menu bar front end for the `agents` script bundled in Contents/Resources.
//
// All behaviour (the pmset flag, busy-agent detection, the auto-pause guard) lives in that
// script so the terminal and the menu bar can never disagree. This app only shows its state,
// runs its subcommands, owns the global hotkey and posts notifications with its own icon.

import AppKit
import Carbon.HIToolbox
import UserNotifications

let bundleID = Bundle.main.bundleIdentifier ?? "io.github.liam-machine.lid-agents"
let stateDir = NSHomeDirectory() + "/.cache/lid-agents"
let logPath = stateDir + "/lid-agents.log"
let launchAgentPath = NSHomeDirectory() + "/Library/LaunchAgents/\(bundleID).plist"

// MARK: - The agents script

struct AgentState {
    var keeping = false
    var busy = 0
    var guardRunning = false
    var battery = 0
    var onBattery = false
    var lidClosed = false
    var setupOK = true
    var idleMinutes = 3
}

enum Agents {
    static let script = Bundle.main.path(forResource: "agents", ofType: nil) ?? ""

    @discardableResult
    static func run(_ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (127, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func state() -> AgentState {
        let f = run(["state"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").map(String.init)
        guard f.count >= 8 else { return AgentState() }
        return AgentState(keeping: f[0] == "keep", busy: Int(f[1]) ?? 0, guardRunning: f[2] == "1",
                          battery: Int(f[3]) ?? 0, onBattery: f[4] == "battery", lidClosed: f[5] == "closed",
                          setupOK: f[6] == "ok", idleMinutes: Int(f[7]) ?? 3)
    }

    /// (name, folder) for each busy agent
    static func busy() -> [(String, String)] {
        run(["busy"]).output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 3, Int(parts[0]) != nil else { return nil }
            let folder = parts.count > 4 ? parts[4...].joined(separator: " ") : ""
            return (parts[1], folder)
        }
    }

    static func lastAutoPauseReason() -> String? {
        guard let text = try? String(contentsOfFile: logPath, encoding: .utf8),
              let line = text.split(separator: "\n").last(where: { $0.contains("auto-pause:") }),
              let range = line.range(of: "auto-pause: ") else { return nil }
        return String(line[range.upperBound...])
    }
}

// MARK: - Global hotkey (Carbon RegisterEventHotKey needs no Accessibility permission)

struct Hotkey {
    let keyCode: UInt32
    let modifiers: UInt32
    let symbols: String
    let menuKey: String
    let menuModifiers: NSEvent.ModifierFlags

    static let fallback = "ctrl+opt+cmd+a"

    static let keys: [String: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "space": kVK_Space,
    ]

    /// Parses "ctrl+opt+cmd+a" style strings; nil for "none" or anything unrecognised.
    static func parse(_ spec: String) -> Hotkey? {
        var mods: UInt32 = 0
        var flags: NSEvent.ModifierFlags = []
        var key: String?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "ctrl", "control": mods |= UInt32(controlKey); flags.insert(.control)
            case "opt", "option", "alt": mods |= UInt32(optionKey); flags.insert(.option)
            case "shift": mods |= UInt32(shiftKey); flags.insert(.shift)
            case "cmd", "command": mods |= UInt32(cmdKey); flags.insert(.command)
            default: key = part
            }
        }
        guard let key, let code = keys[key] else { return nil }
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        symbols += key == "space" ? "Space" : key.uppercased()
        return Hotkey(keyCode: UInt32(code), modifiers: mods, symbols: symbols,
                      menuKey: key == "space" ? " " : key, menuModifiers: flags)
    }

    static var configured: Hotkey? {
        let spec = UserDefaults.standard.string(forKey: "Hotkey") ?? fallback
        return spec.lowercased() == "none" ? nil : (parse(spec) ?? parse(fallback))
    }
}

var hotkeyHandler: (() -> Void)?

func registerHotkey(_ hotkey: Hotkey) {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        DispatchQueue.main.async { hotkeyHandler?() }
        return noErr
    }, 1, &spec, nil, nil)
    var ref: EventHotKeyRef?
    let id = EventHotKeyID(signature: OSType(0x4C414754), id: 1)   // 'LAGT'
    RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &ref)
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let hotkey = Hotkey.configured
    var state = AgentState()
    var acting = false          // a change this app made, so it isn't reported as an auto-pause
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading

        if let hotkey {
            hotkeyHandler = { [weak self] in self?.toggle() }
            registerHotkey(hotkey)
        }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert]) { [weak self] granted, _ in
            guard granted, !UserDefaults.standard.bool(forKey: "Welcomed") else { return }
            UserDefaults.standard.set(true, forKey: "Welcomed")
            let how = self?.hotkey.map { "Press \($0.symbols) or click" } ?? "Click"
            self?.notify("Lid Agents is ready", "\(how) the cup in the menu bar to keep agents running with the lid closed.")
        }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    // Show banners even while the menu is open (the app counts as frontmost then)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: State

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let next = Agents.state()
            DispatchQueue.main.async { self.apply(next) }
        }
    }

    func apply(_ next: AgentState) {
        if state.keeping && !next.keeping && !acting {
            notify("Agents paused", "Closing the lid sleeps the Mac again (\(Agents.lastAutoPauseReason() ?? "turned off elsewhere")).")
        }
        state = next
        let button = statusItem.button
        let symbol = next.keeping ? "cup.and.saucer.fill" : "cup.and.saucer"
        button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: next.keeping ? "Agents keep running" : "Agents pause")
        button?.image?.isTemplate = true
        button?.title = next.keeping ? " \(next.busy)" : ""
        button?.toolTip = next.keeping ? "Lid closed → agents keep running" : "Lid closed → Mac sleeps, agents pause"
    }

    func perform(_ args: [String]) {
        // A held hotkey auto-repeats; a second toggle before the first lands would undo it
        guard !acting else { return }
        acting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Agents.run(args)
            let next = Agents.state()
            DispatchQueue.main.async {
                if result.status != 0 {
                    let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.notify("Lid Agents couldn't change the setting", message.isEmpty ? "Run `agents install` in a terminal." : message)
                } else if next.keeping {
                    let always = args.contains("--always")
                    self.notify("Agents keep running",
                                always ? "Lid closed won't sleep the Mac, busy or not (3h)."
                                    : next.busy == 0 ? "None busy yet: pauses in ~\(next.idleMinutes) min unless one starts."
                                    : "\(next.busy) busy. Close the lid whenever.")
                } else {
                    self.notify("Agents pause", "Closing the lid sleeps the Mac.")
                }
                self.apply(next)
                self.acting = false
            }
        }
    }

    @objc func toggle() { perform(state.keeping ? ["pause"] : ["keep"]) }
    @objc func keep() { perform(["keep"]) }
    @objc func keepAlways() { perform(["keep", "--always", "3"]) }
    @objc func pause() { perform(["pause"]) }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        apply(Agents.state())
        let busy = Agents.busy()
        menu.removeAllItems()

        func info(_ title: String, symbol: String? = nil) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(item)
        }
        func action(_ title: String, _ selector: Selector, symbol: String, hotkey: Hotkey? = nil) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: hotkey?.menuKey ?? "")
            item.keyEquivalentModifierMask = hotkey?.menuModifiers ?? []
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }

        if state.keeping {
            info("Lid closed → agents keep running", symbol: "cup.and.saucer.fill")
        } else {
            info("Lid closed → Mac sleeps, agents pause", symbol: "moon.zzz")
        }
        info("\(state.busy) agent\(state.busy == 1 ? "" : "s") busy · battery \(state.battery)%\(state.onBattery ? "" : " (charging)")")
        if !state.setupOK { info("Setup incomplete: run `agents install`", symbol: "exclamationmark.triangle") }
        menu.addItem(.separator())

        if state.keeping {
            action("Pause agents when the lid closes", #selector(pause), symbol: "moon.zzz", hotkey: hotkey)
        } else {
            action("Keep agents running with the lid closed", #selector(keep), symbol: "cup.and.saucer.fill", hotkey: hotkey)
            action("Keep running even when idle (3h)", #selector(keepAlways), symbol: "clock")
        }
        menu.addItem(.separator())

        let busyItem = NSMenuItem(title: "Busy agents", action: nil, keyEquivalent: "")
        let busyMenu = NSMenu()
        if busy.isEmpty {
            busyMenu.addItem(withTitle: "None right now", action: nil, keyEquivalent: "").isEnabled = false
        }
        for (name, folder) in busy {
            let title = folder.isEmpty ? name : "\(name) — \((folder as NSString).abbreviatingWithTildeInPath)"
            busyMenu.addItem(withTitle: title, action: nil, keyEquivalent: "").isEnabled = false
        }
        busyItem.submenu = busyMenu
        menu.addItem(busyItem)

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = FileManager.default.fileExists(atPath: launchAgentPath) ? .on : .off
        menu.addItem(login)
        let logItem = NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Lid Agents", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func openLog() {
        if !FileManager.default.fileExists(atPath: logPath) {
            try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    @objc func toggleLogin() {
        if FileManager.default.fileExists(atPath: launchAgentPath) {
            try? FileManager.default.removeItem(atPath: launchAgentPath)
            return
        }
        let plist: [String: Any] = [
            "Label": bundleID,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
        ]
        try? FileManager.default.createDirectory(atPath: (launchAgentPath as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            FileManager.default.createFile(atPath: launchAgentPath, contents: data)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
