import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class UsageStore: ObservableObject {
    @Published var codex: UsageSnapshot?
    @Published var cursor: UsageSnapshot?
    @Published var codexError: String?
    @Published var cursorError: String?
    @Published var refreshing = false
    @Published var interval = UserDefaults.standard.integer(forKey: "refreshMinutes") == 0 ? 5 : UserDefaults.standard.integer(forKey: "refreshMinutes")
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var settingsError: String?
    var onChange: (() -> Void)?
    private var timer: Timer?

    func start() { reschedule(); refresh() }

    func reschedule() {
        timer?.invalidate()
        UserDefaults.standard.set(interval, forKey: "refreshMinutes")
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        onChange?()
        Task {
            async let first: Void = updateCodex()
            async let second: Void = updateCursor()
            _ = await (first, second)
            refreshing = false
            onChange?()
        }
    }

    private func updateCodex() async {
        do { codex = try await CodexProvider.fetch(); codexError = nil }
        catch { codexError = error.localizedDescription }
        onChange?()
    }

    private func updateCursor() async {
        do { cursor = try await CursorProvider.fetch(); cursorError = nil }
        catch { cursorError = error.localizedDescription }
        onChange?()
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            settingsError = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许 QuotaBar。" : nil
            if settingsError != nil { SMAppService.openSystemSettingsLoginItems() }
        } catch { settingsError = "无法修改登录项：\(error.localizedDescription)" }
    }
}

struct QuotaPanel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text("剩余额度").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { store.refresh() } label: {
                    if store.refreshing { ProgressView().controlSize(.mini).frame(width: 16, height: 16) }
                    else { Image(systemName: "arrow.clockwise").frame(width: 16, height: 16) }
                }.buttonStyle(.borderless).disabled(store.refreshing).help("刷新额度")
            }
            providerCard("Codex", snapshot: store.codex, error: store.codexError, tint: Color(red: 0.15, green: 0.66, blue: 0.48))
            providerCard("Cursor", snapshot: store.cursor, error: store.cursorError, tint: Color(red: 0.37, green: 0.48, blue: 0.94))
            Divider()
            HStack(spacing: 5) {
                Picker("自动刷新", selection: $store.interval) {
                    Text("每 1 分钟").tag(1)
                    Text("每 5 分钟").tag(5)
                    Text("每 15 分钟").tag(15)
                }.labelsHidden().frame(width: 96).onChange(of: store.interval) { _ in store.reschedule() }
                Spacer(minLength: 5)
                Toggle("登录时启动", isOn: Binding(get: { store.loginEnabled }, set: { store.setLogin($0) }))
                    .toggleStyle(.checkbox)
                Spacer(minLength: 5)
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }.font(.system(size: 10))
            if let error = store.settingsError { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(12).frame(width: 350)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
    }

    private func providerCard(_ name: String, snapshot: UsageSnapshot?, error: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(name).font(.system(size: 13, weight: .semibold))
                if let plan = snapshot?.plan {
                    Text(plan).font(.system(size: 9, weight: .medium)).foregroundStyle(tint)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(tint.opacity(0.10), in: Capsule())
                }
                Spacer()
                if let date = snapshot?.fetchedAt {
                    Text(date.formatted(.dateTime.hour().minute())).font(.system(size: 9)).foregroundStyle(.tertiary)
                        .help("最近更新")
                }
                Button { NSWorkspace.shared.open(URL(string: name == "Codex" ? "https://chatgpt.com/codex/settings/usage" : "https://cursor.com/dashboard/spending")!) } label: {
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                }.buttonStyle(.borderless).help("打开用量页面")
            }
            if let snapshot {
                ForEach(snapshot.quotas) { quota in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(quota.label).font(.system(size: 11))
                            Spacer()
                            Text(quota.resetsAt.map { "重置 \($0.formatted(.dateTime.month().day().hour().minute()))" } ?? "重置时间未知")
                                .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize()
                            Text(quota.formatted).font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(quota.remaining <= 15 ? .orange : tint)
                                .frame(width: 48, alignment: .trailing)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(tint.opacity(0.12))
                                Capsule().fill(quota.remaining <= 15 ? .orange : tint)
                                    .frame(width: geometry.size.width * quota.remaining / 100)
                            }
                        }.frame(height: 4)
                        if let detail = quota.detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                if let note = snapshot.note {
                    Text(note).font(.system(size: 9)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if error == nil {
                Text("正在读取用量…").font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                Label("\(snapshot != nil ? "数据已过期 · " : "")\(error)", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}

// A template image preserves the native menu-bar tint and highlighted-button behavior.
// Fixed column widths keep the item steady as values change.
@MainActor
enum StatusLabelRenderer {
    static func image(codex: String, cursor: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 98, height: 24), flipped: false) { _ in
            for (index, label, value) in [(0, "Codex", codex), (1, "Cursor", cursor)] {
                let x = CGFloat(index) * 50
                func draw(_ text: String, font: NSFont, y: CGFloat) {
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
                    let size = (text as NSString).size(withAttributes: attributes)
                    (text as NSString).draw(at: NSPoint(x: x + (48 - size.width) / 2, y: y), withAttributes: attributes)
                }
                draw(label, font: .systemFont(ofSize: 8, weight: .semibold), y: 13)
                draw(value, font: .monospacedDigitSystemFont(ofSize: 11, weight: .bold), y: 0)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleNone
        popover.behavior = .transient
        let controller = NSHostingController(rootView: QuotaPanel(store: store))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        store.onChange = { [weak self] in self?.updateTitle() }
        updateTitle()
        store.start()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp), name: NSWorkspace.didWakeNotification, object: nil)
        if ProcessInfo.processInfo.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.togglePanel() }
        }
    }

    private func updateTitle() {
        func value(_ snapshot: UsageSnapshot?, _ error: String?) -> String {
            if error != nil { return snapshot.map { "\($0.summary)!" } ?? "!" }
            return snapshot?.summary ?? "…"
        }
        let codex = value(store.codex, store.codexError)
        let cursor = value(store.cursor, store.cursorError)
        statusItem.button?.title = ""
        statusItem.button?.image = StatusLabelRenderer.image(codex: codex, cursor: cursor)
        statusItem.button?.setAccessibilityLabel("Codex 剩余 \(codex)，Cursor 剩余 \(cursor)")
        statusItem.button?.toolTip = "剩余使用量 · 点击查看各额度窗口和重置时间\(store.refreshing ? " · 刷新中" : "")"
    }

    @objc private func wokeUp() { store.refresh() }
    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

@main
enum QuotaBarMain {
    @MainActor
    static func main() async {
        if CommandLine.arguments.contains("--check") {
            async let first = report("Codex") { try await CodexProvider.fetch() }
            async let second = report("Cursor") { try await CursorProvider.fetch() }
            let (codexOK, cursorOK) = await (first, second)
            exit(codexOK && cursorOK ? 0 : 1)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            await renderPreview(directory: CommandLine.arguments[index + 1])
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    // Development preview renders only our own views, without capturing the desktop.
    @MainActor
    private static func renderPreview(directory: String) async {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let store = UsageStore()
        if CommandLine.arguments.contains("--demo") {
            store.loginEnabled = false
            let date = Date(timeIntervalSince1970: 1791590400)
            store.codex = UsageSnapshot(provider: "Codex", plan: "Plus", quotas: [
                Quota(id: "codex.primary", label: "5 小时额度", remaining: 72, resetsAt: date.addingTimeInterval(3600)),
                Quota(id: "codex.secondary", label: "每周额度", remaining: 54, resetsAt: date.addingTimeInterval(604800))
            ], summaryRemaining: 54, note: "菜单栏显示主额度各窗口中较低的剩余比例。", fetchedAt: date)
            store.cursor = UsageSnapshot(provider: "Cursor", plan: "Pro", quotas: [
                Quota(id: "total", label: "总额度", remaining: 68.4, resetsAt: date.addingTimeInterval(2592000)),
                Quota(id: "auto", label: "Cursor 模型池", remaining: 76, resetsAt: date.addingTimeInterval(2592000)),
                Quota(id: "api", label: "其他模型池", remaining: 61, resetsAt: date.addingTimeInterval(2592000))
            ], summaryRemaining: 68.4, note: "基础额度剩余 $12.00 / $20.00；与总额度比例口径不同。", fetchedAt: date)
        } else {
            do { store.codex = try await CodexProvider.fetch() } catch { store.codexError = error.localizedDescription }
            do { store.cursor = try await CursorProvider.fetch() } catch { store.cursorError = error.localizedDescription }
        }
        let destination = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                let view = NSHostingView(rootView: QuotaPanel(store: store))
                view.appearance = NSAppearance(named: appearance)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = view.appearance
                window.contentView = view
                view.layoutSubtreeIfNeeded()
                let size = view.fittingSize
                view.setFrameSize(size)
                window.setContentSize(size)
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try data.write(to: destination.appendingPathComponent("panel-\(name).png"))
                    print("\(name) panel: \(Int(size.width)) × \(Int(size.height)) pt")
                }
            }
            let status = StatusLabelRenderer.image(codex: store.codex?.summary ?? "!", cursor: store.cursor?.summary ?? "!")
            let statusPreview = NSImage(size: NSSize(width: 294, height: 72), flipped: false) { bounds in
                NSColor.white.setFill()
                bounds.fill()
                status.draw(in: bounds)
                return true
            }
            if let tiff = statusPreview.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) {
                try data.write(to: destination.appendingPathComponent("status-label.png"))
            }
        } catch { print("Preview: \(error.localizedDescription)") }
    }

    private static func report(_ provider: String, fetch: () async throws -> UsageSnapshot) async -> Bool {
        do {
            let snapshot = try await fetch()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            print(String(data: try encoder.encode(snapshot), encoding: .utf8)!)
            return true
        } catch { print("\(provider): \(error.localizedDescription)"); return false }
    }
}
