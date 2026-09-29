import Cocoa
import SwiftUI
import UniformTypeIdentifiers
import Darwin

// MARK: - Models

struct AppItem: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var path: String
    var bundleId: String
    var enabled: Bool
    var delaySeconds: Double
    var note: String
}

struct LauncherConfig: Codable, Equatable {
    var autoStartFlClashCore: Bool
    var waitForFlClashPort: Bool
    var flClashPort: Int
    var lastLaunchedBootId: String
    var apps: [AppItem]

    static func defaultApps() -> [AppItem] {
        return [
            AppItem(
                id: "flclash",
                name: "FlClash",
                path: "/Applications/FlClash.app",
                bundleId: "com.follow.clash",
                enabled: true,
                delaySeconds: 2.0,
                note: "优先启动 · 自动激活代理核心 & 7890端口"
            ),
            AppItem(
                id: "easycliproxyapi",
                name: "EasyCLIProxyAPI",
                path: "/Applications/EasyCLIProxyAPI.app",
                bundleId: "com.cpa.gui",
                enabled: true,
                delaySeconds: 1.5,
                note: "本地 CLI 代理接口服务"
            ),
            AppItem(
                id: "ccswitch",
                name: "CC Switch",
                path: "/Applications/CC Switch.app",
                bundleId: "com.ccswitch.desktop",
                enabled: true,
                delaySeconds: 1.5,
                note: "AI 配置快速切换中心"
            ),
            AppItem(
                id: "chatgpt",
                name: "ChatGPT",
                path: "/Applications/ChatGPT.app",
                bundleId: "com.openai.codex",
                enabled: true,
                delaySeconds: 1.5,
                note: "OpenAI 桌面终端"
            ),
            AppItem(
                id: "googlechrome",
                name: "Google Chrome",
                path: "/Applications/Google Chrome.app",
                bundleId: "com.google.Chrome",
                enabled: true,
                delaySeconds: 1.5,
                note: "主力网页浏览器"
            ),
            AppItem(
                id: "muse",
                name: "Muse",
                path: "/Applications/Muse.app",
                bundleId: "com.meta.endo",
                enabled: true,
                delaySeconds: 1.5,
                note: "灵感与工作空间"
            ),
            AppItem(
                id: "wechat",
                name: "微信",
                path: "/Applications/WeChat.app",
                bundleId: "com.tencent.xinWeChat",
                enabled: true,
                delaySeconds: 1.0,
                note: "即时通讯与日常办公"
            )
        ]
    }

    static func defaultConfig() -> LauncherConfig {
        return LauncherConfig(
            autoStartFlClashCore: true,
            waitForFlClashPort: true,
            flClashPort: 7890,
            lastLaunchedBootId: "",
            apps: defaultApps()
        )
    }
}

// MARK: - System Helpers

enum SystemHelper {
    static let configDir = NSHomeDirectory() + "/.config/oneclick_launcher"
    static let configFile = configDir + "/config.json"

    static func loadConfig() -> LauncherConfig {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir) {
            try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configFile)),
              let decoded = try? JSONDecoder().decode(LauncherConfig.self, from: data) else {
            let def = LauncherConfig.defaultConfig()
            saveConfig(def)
            return def
        }
        return decoded
    }

    static func saveConfig(_ config: LauncherConfig) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir) {
            try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: URL(fileURLWithPath: configFile), options: .atomic)
        }
    }

    static func getCurrentBootId() -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        task.arguments = ["-n", "kern.boottime"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !str.isEmpty {
                return str
            }
        } catch {}
        return "boot-default"
    }

    static func isLocalPortOpen(port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    static func ensureFlClashAutoRunEnabled() {
        let plistPath = NSHomeDirectory() + "/Library/Preferences/com.follow.clash.plist"
        guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plistObj = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let jsonStr = plistObj["flutter.config"] as? String,
              let jsonData = jsonStr.data(using: .utf8),
              var cfgDict = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            return
        }

        var appSettings = (cfgDict["appSettingProps"] as? [String: Any]) ?? [:]
        let currentAutoRun = (appSettings["autoRun"] as? Bool) ?? false
        if !currentAutoRun {
            appSettings["autoRun"] = true
            cfgDict["appSettingProps"] = appSettings
            if let updatedData = try? JSONSerialization.data(withJSONObject: cfgDict, options: []),
               let updatedStr = String(data: updatedData, encoding: .utf8) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
                proc.arguments = ["write", "com.follow.clash", "flutter.config", "-string", updatedStr]
                try? proc.run()
                proc.waitUntilExit()
                CFPreferencesAppSynchronize("com.follow.clash" as CFString)
            }
        }
    }

    static func isAppRunning(_ item: AppItem) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if !item.bundleId.isEmpty, app.bundleIdentifier == item.bundleId {
                return true
            }
            if let url = app.bundleURL, url.path == item.path {
                return true
            }
            if let locName = app.localizedName, locName.lowercased() == item.name.lowercased() {
                return true
            }
        }
        return false
    }

    static func sendNotification(title: String, subtitle: String = "", message: String) {
        DispatchQueue.global(qos: .utility).async {
            let safeMsg = message.replacingOccurrences(of: "\"", with: "\\\"")
            let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            let safeSub = subtitle.replacingOccurrences(of: "\"", with: "\\\"")
            let script: String
            if safeSub.isEmpty {
                script = "display notification \"\(safeMsg)\" with title \"\(safeTitle)\""
            } else {
                script = "display notification \"\(safeMsg)\" with title \"\(safeTitle)\" subtitle \"\(safeSub)\""
            }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            try? proc.run()
        }
    }

    static func launchSingleApp(_ item: AppItem, autoStartClash: Bool) {
        if item.path.lowercased().contains("flclash") && autoStartClash {
            ensureFlClashAutoRunEnabled()
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", item.path]
        try? proc.run()
        proc.waitUntilExit()
    }

    static func bundleIdForApp(at path: String) -> String {
        if let bundle = Bundle(path: path), let bid = bundle.bundleIdentifier {
            return bid
        }
        return ""
    }

    static func displayNameForApp(at path: String) -> String {
        let fm = FileManager.default
        let display = fm.displayName(atPath: path)
        if display.hasSuffix(".app") {
            return String(display.dropLast(4))
        }
        return display
    }
}

// MARK: - ViewModel

class LauncherViewModel: ObservableObject {
    @Published var config: LauncherConfig {
        didSet {
            SystemHelper.saveConfig(config)
        }
    }
    @Published var currentBootId: String
    @Published var isLaunching: Bool = false
    @Published var currentLaunchingAppId: String? = nil
    @Published var launchProgress: Double = 0.0
    @Published var statusBannerText: String = "准备就绪"
    @Published var isPort7890Open: Bool = false
    @Published var runningMap: [String: Bool] = [:]
    @Published var saveToastVisible: Bool = false
    @Published var hoveredAppId: String? = nil

    private var timer: Timer?

    init(initialConfig: LauncherConfig, bootId: String) {
        self.config = initialConfig
        self.currentBootId = bootId
        refreshLiveStates()
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshLiveStates()
        }
    }

    func refreshLiveStates() {
        let portOpen = SystemHelper.isLocalPortOpen(port: config.flClashPort)
        var map: [String: Bool] = [:]
        for item in config.apps {
            map[item.id] = SystemHelper.isAppRunning(item)
        }
        DispatchQueue.main.async {
            self.isPort7890Open = portOpen
            self.runningMap = map
        }
    }

    var isBootAlreadyLaunched: Bool {
        return config.lastLaunchedBootId == currentBootId
    }

    var enabledAppsCount: Int {
        config.apps.filter { $0.enabled }.count
    }

    var totalEstimatedDelay: Double {
        config.apps.filter { $0.enabled }.reduce(0.0) { $0 + $1.delaySeconds }
    }

    func toggleNextClickMode() {
        if isBootAlreadyLaunched {
            config.lastLaunchedBootId = ""
            showSaveToast("已设为：下次点击直接一键启动")
        } else {
            config.lastLaunchedBootId = currentBootId
            showSaveToast("已设为：下次点击打开配置界面")
        }
    }

    func moveApp(at index: Int, direction: Int) {
        let target = index + direction
        guard target >= 0 && target < config.apps.count else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            config.apps.swapAt(index, target)
        }
        showSaveToast("启动顺序已更新")
    }

    func removeApp(id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            config.apps.removeAll { $0.id == id }
        }
        showSaveToast("已移除应用")
    }

    func adjustDelay(id: String, delta: Double) {
        guard let idx = config.apps.firstIndex(where: { $0.id == id }) else { return }
        let newVal = max(0.5, min(15.0, (config.apps[idx].delaySeconds + delta)))
        config.apps[idx].delaySeconds = (newVal * 2).rounded() / 2
        showSaveToast("等待时间已保存")
    }

    func restoreDefaults() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            let boot = config.lastLaunchedBootId
            var def = LauncherConfig.defaultConfig()
            def.lastLaunchedBootId = boot
            config = def
        }
        showSaveToast("已恢复默认 7 大应用队列")
    }

    func addAppViaPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择要加入一键启动的应用程序 (.app)"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [UTType.application]
        }

        if panel.runModal() == .OK {
            for url in panel.urls {
                let path = url.path
                if config.apps.contains(where: { $0.path == path }) {
                    continue
                }
                let name = SystemHelper.displayNameForApp(at: path)
                let bid = SystemHelper.bundleIdForApp(at: path)
                let newItem = AppItem(
                    id: UUID().uuidString.lowercased(),
                    name: name,
                    path: path,
                    bundleId: bid,
                    enabled: true,
                    delaySeconds: 1.5,
                    note: "自定义添加应用"
                )
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    config.apps.append(newItem)
                }
            }
            refreshLiveStates()
            showSaveToast("已成功添加新应用")
        }
    }

    func showSaveToast(_ text: String = "配置已自动保存") {
        statusBannerText = text
        withAnimation(.easeInOut(duration: 0.2)) {
            saveToastVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            withAnimation(.easeInOut(duration: 0.25)) {
                self?.saveToastVisible = false
            }
        }
    }

    func executeLaunchSequence(autoTerminateWhenDone: Bool = false) {
        guard !isLaunching else { return }
        let enabledApps = config.apps.filter { $0.enabled }
        guard !enabledApps.isEmpty else {
            showSaveToast("请至少勾选启用一个应用")
            return
        }

        isLaunching = true
        launchProgress = 0.0
        config.lastLaunchedBootId = currentBootId

        SystemHelper.sendNotification(
            title: "一键启动 · 极光智控",
            subtitle: "开始按序拉起 \(enabledApps.count) 个应用",
            message: enabledApps.map { $0.name }.joined(separator: " → ")
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let total = Double(enabledApps.count)

            for (idx, item) in enabledApps.enumerated() {
                DispatchQueue.main.async {
                    self.currentLaunchingAppId = item.id
                    self.statusBannerText = "正在启动 (\(idx + 1)/\(enabledApps.count))：\(item.name)..."
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.launchProgress = Double(idx) / total
                    }
                }

                SystemHelper.launchSingleApp(item, autoStartClash: self.config.autoStartFlClashCore)

                if item.path.lowercased().contains("flclash") && self.config.waitForFlClashPort {
                    let port = self.config.flClashPort
                    let startWait = Date()
                    while Date().timeIntervalSince(startWait) < 7.0 {
                        if SystemHelper.isLocalPortOpen(port: port) {
                            break
                        }
                        Thread.sleep(forTimeInterval: 0.25)
                    }
                }

                Thread.sleep(forTimeInterval: item.delaySeconds)
                self.refreshLiveStates()

                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.launchProgress = Double(idx + 1) / total
                    }
                }
            }

            DispatchQueue.main.async {
                self.currentLaunchingAppId = nil
                self.statusBannerText = "🎉 全部 \(enabledApps.count) 个应用已按序启动完成！"
                self.refreshLiveStates()
                SystemHelper.sendNotification(
                    title: "一键启动完成 🎉",
                    subtitle: "您的工作环境已全部就绪",
                    message: enabledApps.map { $0.name }.joined(separator: " · ")
                )

                if autoTerminateWhenDone {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                        NSApp.terminate(nil)
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.isLaunching = false
                    }
                }
            }
        }
    }
}

// MARK: - Visual Styling Helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct AuroraBackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "0B0E17"),
                    Color(hex: "111625"),
                    Color(hex: "0D101B")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "00E5FF").opacity(0.18), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: -240, y: -220)
                .blur(radius: 30)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "9D4EDD").opacity(0.22), Color(hex: "FF2E93").opacity(0.08), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 280
                    )
                )
                .frame(width: 540, height: 540)
                .offset(x: 240, y: -180)
                .blur(radius: 35)
        }
        .ignoresSafeArea()
    }
}

// MARK: - First Boot Compact HUD View

struct BootLaunchHUDView: View {
    @ObservedObject var vm: LauncherViewModel
    var onSwitchToConfig: () -> Void

    var body: some View {
        ZStack {
            AuroraBackgroundView()

            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: "/Applications/一键启动.app"))
                        .resizable()
                        .frame(width: 52, height: 52)
                        .shadow(color: Color(hex: "00E5FF").opacity(0.35), radius: 10, x: 0, y: 2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("一键启动 · 极光智控")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)

                            Text("开机首启模式")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: "00F5D4"))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color(hex: "00F5D4").opacity(0.15))
                                .clipShape(Capsule())
                        }

                        Text(vm.statusBannerText)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.8))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: onSwitchToConfig) {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text("打开配置")
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.09))
                            .frame(height: 8)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "00F5D4"), Color(hex: "00BBF9"), Color(hex: "9B5DE5"), Color(hex: "F15BB5")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(12, geo.size.width * CGFloat(vm.launchProgress)), height: 8)
                            .shadow(color: Color(hex: "00BBF9").opacity(0.5), radius: 6)
                    }
                }
                .frame(height: 8)

                HStack(spacing: 12) {
                    ForEach(vm.config.apps.filter { $0.enabled }) { item in
                        let isCurrent = (vm.currentLaunchingAppId == item.id)
                        let isRunning = (vm.runningMap[item.id] ?? false)
                        VStack(spacing: 4) {
                            ZStack(alignment: .bottomTrailing) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .scaleEffect(isCurrent ? 1.15 : 1.0)
                                    .opacity(isRunning || isCurrent ? 1.0 : 0.45)

                                Circle()
                                    .fill(isRunning ? Color(hex: "10B981") : (isCurrent ? Color(hex: "00E5FF") : Color.gray.opacity(0.4)))
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(Color.black, lineWidth: 1.2))
                            }
                            Text(item.name)
                                .font(.system(size: 10, weight: isCurrent ? .bold : .regular))
                                .foregroundColor(isCurrent ? Color(hex: "00F5D4") : .white.opacity(0.7))
                                .lineLimit(1)
                                .frame(maxWidth: 64)
                        }
                    }
                }
            }
            .padding(22)
        }
        .frame(width: 560, height: 170)
    }
}

// MARK: - Main Configuration Dashboard View

struct ConfigDashboardView: View {
    @ObservedObject var vm: LauncherViewModel

    var body: some View {
        ZStack {
            AuroraBackgroundView()

            VStack(spacing: 12) {
                // 1. Top Hero Header
                headerBanner

                // 2. FlClash Smart Proxy Card
                flClashSmartCard

                // 3. Queue Section Toolbar
                queueToolbar

                // 4. Scrollable App Cards
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 7) {
                        ForEach(Array(vm.config.apps.enumerated()), id: \.element.id) { index, item in
                            AppRowCardView(
                                index: index,
                                totalCount: vm.config.apps.count,
                                item: binding(for: item),
                                isRunning: vm.runningMap[item.id] ?? false,
                                isCurrentlyLaunching: vm.currentLaunchingAppId == item.id,
                                onMoveUp: { vm.moveApp(at: index, direction: -1) },
                                onMoveDown: { vm.moveApp(at: index, direction: 1) },
                                onAdjustDelay: { delta in vm.adjustDelay(id: item.id, delta: delta) },
                                onDelete: { vm.removeApp(id: item.id) },
                                isHovered: vm.hoveredAppId == item.id,
                                onHoverChange: { h in
                                    vm.hoveredAppId = h ? item.id : (vm.hoveredAppId == item.id ? nil : vm.hoveredAppId)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                }

                // 5. Bottom Footer Bar
                footerBar
            }
            .padding(.top, 32)
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 780, idealWidth: 820, minHeight: 720, idealHeight: 760)
    }

    private func binding(for item: AppItem) -> Binding<AppItem> {
        guard let idx = vm.config.apps.firstIndex(where: { $0.id == item.id }) else {
            return .constant(item)
        }
        return $vm.config.apps[idx]
    }

    // MARK: Subviews

    private var headerBanner: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "00E5FF").opacity(0.3), Color(hex: "9D4EDD").opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .blur(radius: 8)

                Image(nsImage: NSWorkspace.shared.icon(forFile: "/Applications/一键启动.app"))
                    .resizable()
                    .frame(width: 54, height: 54)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text("一键启动 · 极光流光智控中心")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(hex: "E0FBFC")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text("Apple Intelligence Edition")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "00F5D4"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule()
                                .fill(Color(hex: "00F5D4").opacity(0.14))
                                .overlay(Capsule().stroke(Color(hex: "00F5D4").opacity(0.35), lineWidth: 0.8))
                        )
                }

                Text("开机第 1 次点击自动按序启动工作环境 · 第 2 次点击进入本配置中心编排软件与顺序")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.68))

                HStack(spacing: 10) {
                    badgePill(
                        icon: "checkmark.circle.fill",
                        text: "已启用 \(vm.enabledAppsCount) / \(vm.config.apps.count) 个软件",
                        color: Color(hex: "00BBF9")
                    )
                    badgePill(
                        icon: "timer",
                        text: String(format: "总间隔 %.1fs", vm.totalEstimatedDelay),
                        color: Color(hex: "9B5DE5")
                    )
                    badgePill(
                        icon: vm.isPort7890Open ? "bolt.shield.fill" : "shield.slash",
                        text: vm.isPort7890Open ? "FlClash 7890 端口已就绪" : "7890 端口未开启",
                        color: vm.isPort7890Open ? Color(hex: "10B981") : Color.orange
                    )
                }
            }

            Spacer()

            Button(action: {
                vm.executeLaunchSequence(autoTerminateWhenDone: false)
            }) {
                HStack(spacing: 8) {
                    if vm.isLaunching {
                        ProgressView()
                            .controlSize(.small)
                            .colorInvert()
                        Text("正在依次启动...")
                            .font(.system(size: 13, weight: .bold))
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12.5, weight: .bold))
                        Text("立即一键启动")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: vm.isLaunching
                            ? [Color.gray.opacity(0.5), Color.gray.opacity(0.4)]
                            : [Color(hex: "00B4D8"), Color(hex: "7209B7"), Color(hex: "F72585")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color(hex: "7209B7").opacity(0.45), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(vm.isLaunching)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "00E5FF").opacity(0.35), Color(hex: "9D4EDD").opacity(0.25), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    private var flClashSmartCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "00F5D4").opacity(0.2), Color(hex: "00BBF9").opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)

                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Color(hex: "00F5D4"))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("FlClash 自动点亮「启动」按钮 & 代理端口智能守卫")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)

                    Text("核心增强")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(Color(hex: "00F5D4"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color(hex: "00F5D4").opacity(0.15))
                        .clipShape(Capsule())
                }
                Text("自动激活 FlClash 内部启动按钮 (autoRun=true)，并检测 7890 端口就绪后再启动后续应用")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 14) {
                Toggle("自动开启核心", isOn: $vm.config.autoStartFlClashCore)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))

                Toggle("7890端口守卫", isOn: $vm.config.waitForFlClashPort)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color(hex: "00F5D4").opacity(0.22), lineWidth: 1)
                )
        )
    }

    private var queueToolbar: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "list.number")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(Color(hex: "00BBF9"))
                Text("启动软件队列与顺序编排（按从上到下依次启动）")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            Spacer()

            if vm.isLaunching {
                HStack(spacing: 8) {
                    Text(vm.statusBannerText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "00F5D4"))
                    ProgressView(value: vm.launchProgress)
                        .frame(width: 90)
                }
                .padding(.trailing, 8)
            }

            Button(action: { vm.addAppViaPanel() }) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                    Text("添加应用")
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(Color(hex: "00F5D4"))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color(hex: "00F5D4").opacity(0.14))
                        .overlay(Capsule().stroke(Color(hex: "00F5D4").opacity(0.4), lineWidth: 0.8))
                )
            }
            .buttonStyle(.plain)

            Button(action: { vm.restoreDefaults() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("恢复默认队列")
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(vm.isBootAlreadyLaunched ? Color(hex: "9B5DE5") : Color(hex: "10B981"))
                    .frame(width: 8, height: 8)

                Text(vm.isBootAlreadyLaunched
                     ? "当前状态：本次开机已执行过首启（下次点击打开本配置界面）"
                     : "当前状态：待执行开机首启（下次点击图标将直接静默启动）")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(1)

                Button(action: { vm.toggleNextClickMode() }) {
                    Text(vm.isBootAlreadyLaunched ? "切换为下次直接启动" : "切换为下次打开配置")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "00BBF9"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .background(Color(hex: "00BBF9").opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if vm.saveToastVisible {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "10B981"))
                    Text(vm.statusBannerText)
                        .foregroundColor(Color(hex: "10B981"))
                        .lineLimit(1)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .transition(.opacity)
            } else {
                Text("✓ 所有修改实时自动保存")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.45))
            }

            Button(action: {
                SystemHelper.saveConfig(vm.config)
                NSApp.terminate(nil)
            }) {
                Text("完成并关闭")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5.5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    private func badgePill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.88))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.13))
                .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.7))
        )
    }
}

// MARK: - Individual App Row Card

struct AppRowCardView: View {
    let index: Int
    let totalCount: Int
    @Binding var item: AppItem
    let isRunning: Bool
    let isCurrentlyLaunching: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onAdjustDelay: (Double) -> Void
    let onDelete: () -> Void
    let isHovered: Bool
    let onHoverChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 13) {
            // 1. Order Badge
            ZStack {
                if !item.enabled {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 48, height: 26)
                    Text("已停用")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                } else if index == 0 {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "00F5D4").opacity(0.25), Color(hex: "00BBF9").opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "00F5D4").opacity(0.5), lineWidth: 0.8)
                        )
                        .frame(width: 48, height: 26)
                    Text("01 优先")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(Color(hex: "00F5D4"))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 48, height: 26)
                    Text(String(format: "#%02d", index + 1))
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                }
            }

            // 2. App Icon
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path))
                .resizable()
                .frame(width: 34, height: 34)
                .opacity(item.enabled ? 1.0 : 0.4)
                .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)

            // 3. Name, Running Status & Path
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(item.enabled ? .white : .white.opacity(0.45))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if isCurrentlyLaunching {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("正在启动...")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: "00E5FF"))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1.5)
                        .background(Color(hex: "00E5FF").opacity(0.15))
                        .clipShape(Capsule())
                        .fixedSize(horizontal: true, vertical: false)
                    } else if isRunning {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: "10B981"))
                                .frame(width: 6, height: 6)
                            Text("运行中")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: "10B981"))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1.5)
                        .background(Color(hex: "10B981").opacity(0.14))
                        .clipShape(Capsule())
                        .fixedSize(horizontal: true, vertical: false)
                    } else {
                        Text("未运行")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.white.opacity(0.38))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1.5)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Capsule())
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if !item.note.isEmpty {
                        Text(item.note)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(Color(hex: "00BBF9").opacity(0.9))
                            .lineLimit(1)
                    }
                }

                Text(item.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer()

            // 4. Delay Control Stepper
            HStack(spacing: 6) {
                Button(action: { onAdjustDelay(-0.5) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 19, height: 19)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "9B5DE5"))
                    Text(String(format: "%.1fs", item.delaySeconds))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.88))
                }
                .frame(width: 46)

                Button(action: { onAdjustDelay(0.5) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 19, height: 19)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.04))
                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.7))
            )

            // 5. Reorder Up / Down Buttons
            HStack(spacing: 4) {
                Button(action: onMoveUp) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(index > 0 ? .white.opacity(0.85) : .white.opacity(0.2))
                        .frame(width: 25, height: 25)
                        .background(Color.white.opacity(index > 0 ? 0.09 : 0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(index == 0)

                Button(action: onMoveDown) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(index < totalCount - 1 ? .white.opacity(0.85) : .white.opacity(0.2))
                        .frame(width: 25, height: 25)
                        .background(Color.white.opacity(index < totalCount - 1 ? 0.09 : 0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(index >= totalCount - 1)
            }

            // 6. Enable Switch
            Toggle("", isOn: $item.enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()

            // 7. Delete Button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Color(hex: "FF595E").opacity(0.85))
                    .frame(width: 25, height: 25)
                    .background(Color(hex: "FF595E").opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7.5)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCurrentlyLaunching
                      ? Color(hex: "00BBF9").opacity(0.14)
                      : (isHovered ? Color.white.opacity(0.085) : Color.white.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isCurrentlyLaunching
                                ? Color(hex: "00F5D4").opacity(0.7)
                                : (isHovered ? Color.white.opacity(0.2) : Color.white.opacity(0.08)),
                            lineWidth: isCurrentlyLaunching ? 1.4 : 0.8
                        )
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                onHoverChange(hovering)
            }
        }
    }
}

// MARK: - App Delegate & Window Routing

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var vm: LauncherViewModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let config = SystemHelper.loadConfig()
        let bootId = SystemHelper.getCurrentBootId()
        vm = LauncherViewModel(initialConfig: config, bootId: bootId)

        let args = CommandLine.arguments
        let forceConfig = args.contains("--config") || NSEvent.modifierFlags.contains(.option)
        let forceLaunch = args.contains("--launch")
        let forceHudOnly = args.contains("--hud")

        let isFirstBootClick = (config.lastLaunchedBootId != bootId)

        if forceHudOnly {
            showBootLaunchHUD()
        } else if forceLaunch || (isFirstBootClick && !forceConfig) {
            showBootLaunchHUD()
            vm.executeLaunchSequence(autoTerminateWhenDone: true)
        } else {
            showConfigWindow()
        }

        if let shotIdx = args.firstIndex(of: "--snapshot"), shotIdx + 1 < args.count {
            let outPath = args[shotIdx + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.captureWindowSnapshot(to: outPath)
                NSApp.terminate(nil)
            }
        }
    }

    func captureWindowSnapshot(to path: String) {
        guard let contentView = window?.contentView else { return }
        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        contentView.cacheDisplay(in: bounds, to: rep)
        if let pngData = rep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: URL(fileURLWithPath: path))
        }
    }

    func showBootLaunchHUD() {
        let hudView = BootLaunchHUDView(vm: vm) { [weak self] in
            self?.switchFromHUDToConfig()
        }
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 170),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.center()
        window.contentView = NSHostingView(rootView: hudView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func switchFromHUDToConfig() {
        vm.isLaunching = false
        window.close()
        showConfigWindow()
    }

    func showConfigWindow() {
        let dashboardView = ConfigDashboardView(vm: vm)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "一键启动 · 极光流光智控中心"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.contentView = NSHostingView(rootView: dashboardView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
