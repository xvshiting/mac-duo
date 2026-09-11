import AppKit
import SwiftUI
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let state = AppState()
    private var status: NSStatusItem!
    private var settings: NSWindow?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var localKeyMonitor: Any?
    private var lastTitle = ""
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "MacDuo 开盖对焦")
        status.button?.imagePosition = .imageLeading
        status.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        state.didUpdate = { [weak self] in self?.refreshStatus() }
        registerHotKey()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let emergencyModifiers: NSEvent.ModifierFlags = [.control, .option, .command]
            let isEmergency = event.keyCode == UInt16(kVK_ANSI_B)
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: emergencyModifiers)
            if isEmergency || (event.keyCode == UInt16(kVK_Escape) && self?.settings?.isKeyWindow == true) {
                self?.state.emergencyClear()
                return nil
            }
            return event
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.state.stop() })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.state.stop() })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.state.start() })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.state.start() })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.state.overlay.rebuild(); self?.state.perspective.rebuild(); self?.state.update()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.state.refreshCapture() })
        state.start()
        showSettings()
    }

    private func refreshStatus() {
        let title = state.enabled ? state.angle.map { " \(Int($0))°" } ?? " —" : " 暂停"
        if title != lastTitle { status.button?.title = title; lastTitle = title }
        status.button?.toolTip = "MacDuo · 清晰点 \(Int(state.focusAngle))° · ⌃⌥⌘B 恢复清晰"
    }

    func menuWillOpen(_ menu: NSMenu) {
        state.menuOpen = true
        menu.removeAllItems()
        let angle = state.angle.map { "\(Int($0))°" } ?? "未连接"
        menu.addItem(withTitle: "MacDuo · 机盖 \(angle)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let toggle = menu.addItem(withTitle: state.enabled ? "暂停开盖效果" : "启用开盖效果", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        let calibration = menu.addItem(withTitle: "将当前角度设为清晰点", action: #selector(calibrate), keyEquivalent: "")
        calibration.target = self; calibration.isEnabled = (state.angle ?? 0) >= 25
        let setting = menu.addItem(withTitle: "设置与预览…", action: #selector(showSettings), keyEquivalent: ",")
        setting.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "退出 MacDuo", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
    }
    func menuDidClose(_ menu: NSMenu) { state.menuOpen = false }
    @objc private func toggleEnabled() { state.stopPreview(); state.enabled.toggle() }
    @objc private func calibrate() { state.calibrate() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    @objc func showSettings() {
        if settings == nil {
            let view = NSHostingView(rootView: SettingsView(state: state))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 650), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "MacDuo"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.setContentSize(view.fittingSize)
            window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            window.delegate = self
            window.center()
            settings = window
        }
        state.settingsVisible = true
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        state.settingsVisible = false
        state.stopPreview()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        state.stop()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }

    private func registerHotKey() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            delegate.state.emergencyClear()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x4D44554F, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr {
            // During an authorization relaunch, the previous process may briefly
            // still own the hotkey. Register again after that process has exited.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.hotKey == nil else { return }
                let retried = RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x4D44554F, id: 1), GetApplicationEventTarget(), 0, &self.hotKey)
                if retried != noErr { NSLog("MacDuo: emergency shortcut unavailable (%d); menu pause remains available", retried) }
            }
        }
    }
}

if CommandLine.arguments.contains("--diagnose") {
    let sensor = LidSensor()
    let overlay = BlurOverlay()
    print("Live backdrop API: \(overlay.available ? "available" : "unavailable")")
    print("Perspective capture permission: \(CGPreflightScreenCaptureAccess())")
    var finished = false
    sensor.start { angle in
        if let angle, !finished { print("Lid sensor: \(angle)°"); finished = true }
    }
    let deadline = Date().addingTimeInterval(3)
    while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    sensor.stop()
    if !finished { print("Lid sensor: unavailable") }
    exit(finished && overlay.available ? 0 : 1)
}
if CommandLine.arguments.contains("--check-perspective") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let effect = PerspectiveOverlay()
    effect.inspectTransparency = true
    var measurementStarted = false
    var finished = false
    func finishReport() {
        guard !finished else { return }
        finished = true
        let count = effect.frameCount
        let report: [String: Any] = ["permission": effect.hasPermission, "frames": count,
                                   "foregroundWindows": effect.foregroundWindowCount,
                                   "desktopWindows": effect.desktopWindowCount,
                                   "transparentForeground": effect.foregroundHasTransparency,
                                   "error": effect.error ?? "none",
                                   "performance": effect.performanceReport]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
            if let index = CommandLine.arguments.firstIndex(of: "--report"), CommandLine.arguments.count > index + 1 {
                try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
            }
        }
        effect.setCaptureEnabled(false)
        exit(count > 10 ? 0 : 1)
    }
    effect.didChange = {
        if effect.isReady {
            _ = effect.apply(angle: 85, focusAngle: 120, radius: 18)
            if !measurementStarted {
                measurementStarted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { finishReport() }
            }
        }
    }
    effect.setCaptureEnabled(true)
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { finishReport() }
    app.run()
    exit(1)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
