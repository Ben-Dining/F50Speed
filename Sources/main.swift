import AppKit
import Foundation
import ServiceManagement
import SystemConfiguration

// F50 Speed — macOS 菜单栏实时网速工具
// 直连中兴 F50 (192.168.0.1) 免登录接口；F50 不可达时自动回退到
// 读取本机 en0 网卡计数，显示 Mac 自身的上下行速率。

// MARK: - 配置

let routerURL = URL(string: "http://192.168.0.1/goform/goform_get_cmd_process?cmd=flux_realtime_tx_thrpt,flux_realtime_rx_thrpt,network_type,network_signalbar,signalbar,wifi_access_sta_num&multi_data=1")!
let webURL = URL(string: "http://192.168.0.1/")!

// MARK: - 偏好

var lang: String {
    get { UserDefaults.standard.string(forKey: "f50.lang") ?? "zh" }
    set { UserDefaults.standard.set(newValue, forKey: "f50.lang") }
}

/// 菜单栏布局："vertical" = 上下两行（默认），"horizontal" = 左右并排
var menuLayout: String {
    get { UserDefaults.standard.string(forKey: "f50.layout") ?? "vertical" }
    set { UserDefaults.standard.set(newValue, forKey: "f50.layout") }
}

/// 速率单位："bits" = Mbps（默认，网络速率），"bytes" = MB/s（下载字节速度）
var speedUnit: String {
    get { UserDefaults.standard.string(forKey: "f50.unit") ?? "bits" }
    set { UserDefaults.standard.set(newValue, forKey: "f50.unit") }
}

func L(_ zh: String, _ en: String) -> String { lang == "zh" ? zh : en }

struct Strings {
    var connecting: String { L("正在连接…", "Connecting…") }
    func unreachable(_ ip: String) -> String { L("F50 连接失败（\(ip)）", "F50 unreachable (\(ip))") }
    func meta(_ net: String, _ sig: Int, _ sta: Int) -> String {
        let n = net.isEmpty ? L("未知网络", "Unknown network") : net
        return L("\(n) · 信号 \(sig)/5 · 在线设备 \(sta)", "\(n) · Signal \(sig)/5 · Devices \(sta)")
    }
    func localMeta(_ ssid: String, _ iface: String) -> String {
        ssid.isEmpty ? L("本机网络（\(iface)）", "This Mac (\(iface))") : L("本机 Wi-Fi：\(ssid)", "This Mac Wi-Fi: \(ssid)")
    }
    var refreshInterval: String { L("刷新间隔", "Refresh interval") }
    var speedUnitMenu: String { L("速率单位", "Speed unit") }
    var unitBits: String { L("Mbps（网络速率）", "Mbps (line rate)") }
    var unitBytes: String { L("MB/s（下载速度）", "MB/s (byte rate)") }
    var showFloat: String { L("显示悬浮窗", "Show floating window") }
    var launchAtLogin: String { L("开机自动启动", "Launch at login") }
    var openAdmin: String { L("打开 F50 管理页", "Open F50 admin page") }
    var quit: String { L("退出 F50 网速", "Quit F50 Speed") }
    var language: String { L("语言", "Language") }
    var layoutMenu: String { L("菜单栏布局", "Menu bar layout") }
    var layoutVertical: String { L("上下显示", "Stacked") }
    var layoutHorizontal: String { L("左右显示", "Side by side") }
    var panelTitle: String { L("F50 网速", "F50 Speed") }
    var tooltip: String { L("F50 网速（▼下行 ▲上行），点击打开菜单", "F50 speed (▼down ▲up) — click for menu") }
    func sec(_ n: Int) -> String { L("\(n) 秒", "\(n)s") }
}

let S = Strings()

// MARK: - 数据

struct Sample {
    var up: Double   // bps
    var down: Double // bps
}

struct RouterInfo {
    var up: Double
    var down: Double
    var network: String
    var signal: Int
    var staNum: Int
}

func fetchRouter(completion: @escaping (RouterInfo?) -> Void) {
    var req = URLRequest(url: routerURL, timeoutInterval: 2)
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    URLSession.shared.dataTask(with: req) { data, _, error in
        guard error == nil, let data = data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { completion(nil); return }
        let num: (String) -> Double = { key in
            if let s = obj[key] as? String, let v = Double(s) { return v }
            if let n = obj[key] as? NSNumber { return n.doubleValue }
            return 0
        }
        let str: (String) -> String = { obj[$0] as? String ?? "" }
        let sigRaw = max(num("network_signalbar"), num("signalbar"))
        completion(RouterInfo(
            up: num("flux_realtime_tx_thrpt"),
            down: num("flux_realtime_rx_thrpt"),
            network: str("network_type"),
            signal: Int(sigRaw),
            staNum: Int(num("wifi_access_sta_num"))
        ))
    }.resume()
}

// MARK: - 本机网卡计数（F50 不可达时的回退来源）

struct NetCounterSample {
    var ibytes: UInt64
    var obytes: UInt64
    var t: TimeInterval
}

/// 当前默认路由所在的接口名（自动适应 USB  tethering / Wi-Fi / 有线）
func primaryInterface() -> String {
    guard let store = SCDynamicStoreCreate(nil, "f50speed" as CFString, nil, nil),
          let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
          let name = dict["PrimaryInterface"] as? String, !name.isEmpty
    else { return "en0" }
    return name
}

func readNetCounters(interface ifname: String) -> (ibytes: UInt64, obytes: UInt64)? {
    var addrs: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
    defer { freeifaddrs(addrs) }
    var ib: UInt64 = 0, ob: UInt64 = 0
    var found = false
    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let ifa = ptr {
        let name = String(cString: ifa.pointee.ifa_name)
        if name == ifname, let data = ifa.pointee.ifa_data {
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            ib = UInt64(d.ifi_ibytes)
            ob = UInt64(d.ifi_obytes)
            found = true
        }
        ptr = ifa.pointee.ifa_next
    }
    return found ? (ib, ob) : nil
}

/// 缓存的 Wi-Fi 名称（60 秒刷新一次，避免频繁起进程）
private var cachedSSID = ""
private var ssidFetchedAt: TimeInterval = 0

func currentWiFiSSID() -> String {
    let now = Date.timeIntervalSinceReferenceDate
    if now - ssidFetchedAt < 60 && !cachedSSID.isEmpty { return cachedSSID }
    ssidFetchedAt = now
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    p.arguments = ["-getairportnetwork", "en0"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do {
        try p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let s = String(data: data, encoding: .utf8), let idx = s.firstIndex(of: ":") {
            cachedSSID = s[s.index(after: idx)...]
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.newlines))
        } else {
            cachedSSID = ""
        }
    } catch {
        cachedSSID = ""
    }
    return cachedSSID
}

// MARK: - 速率格式化

/// 返回 (数值文本, 完整单位)。bytes = true 时按字节换算（÷8）。
func formatSpeed(_ bps: Double, bytes: Bool) -> (String, String) {
    let v = bytes ? bps / 8 : bps
    if v >= 1e9 { return (String(format: "%.2f", v / 1e9), bytes ? "GB/s" : "Gbps") }
    if v >= 1e6 { return (v >= 1e8 ? String(format: "%.0f", v / 1e6) : String(format: "%.1f", v / 1e6), bytes ? "MB/s" : "Mbps") }
    if v >= 1e3 { return (String(format: "%.0f", v / 1e3), bytes ? "KB/s" : "Kbps") }
    return (String(format: "%.0f", v), bytes ? "B/s" : "bps")
}

/// 菜单栏紧凑格式：数值 + 短后缀（24.3M / 3.0MB），低速率时保留完整单位
func formatSpeedCompact(_ bps: Double, bytes: Bool) -> String {
    let (txt, unit) = formatSpeed(bps, bytes: bytes)
    var suffix = unit.replacingOccurrences(of: "bps", with: "").replacingOccurrences(of: "/s", with: "")
    if suffix.isEmpty { suffix = bytes ? "B" : "bps" }
    return txt + suffix
}

// MARK: - 悬浮窗速率曲线

final class SparklineView: NSView {
    var history: [Sample] = [] { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        guard history.count > 1 else { return }
        let maxV = max(history.map(\.down).max() ?? 1, history.map(\.up).max() ?? 1, 1)
        func path(_ key: KeyPath<Sample, Double>) -> NSBezierPath {
            let p = NSBezierPath()
            for (i, s) in history.enumerated() {
                let x = bounds.minX + bounds.width * CGFloat(i) / CGFloat(history.count - 1)
                let y = bounds.minY + (bounds.height - 4) * CGFloat(s[keyPath: key] / maxV) + 2
                i == 0 ? p.move(to: NSPoint(x: x, y: y)) : p.line(to: NSPoint(x: x, y: y))
            }
            return p
        }
        let downColor = NSColor.systemBlue
        let upColor = NSColor.systemOrange
        let fill = path(\.down)
        fill.line(to: NSPoint(x: bounds.maxX, y: bounds.minY))
        fill.line(to: NSPoint(x: bounds.minX, y: bounds.minY))
        fill.close()
        downColor.withAlphaComponent(0.12).setFill()
        fill.fill()
        upColor.setStroke(); path(\.up).stroke()
        downColor.setStroke(); path(\.down).stroke()
    }
}

// MARK: - 主控制器

final class F50Controller: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var interval: TimeInterval = 1
    private var fetching = false

    /// 最近展示的速率信息（nil = 都拿不到）
    private var latestUp: Double?
    private var latestDown: Double?
    private var latestMeta: String = ""
    private var history: [Sample] = []

    /// 本机网卡计数上次采样
    private var lastCounter: NetCounterSample?

    // 菜单（语言切换时整体重建）
    private var headerItem: NSMenuItem = NSMenuItem()
    private var intervalMenu = NSMenu()
    private var unitMenu = NSMenu()
    private var floatItem: NSMenuItem = NSMenuItem()
    private var loginItem: NSMenuItem = NSMenuItem()

    // 悬浮窗
    private var panel: NSPanel?
    private var floatDown: NSTextField?
    private var floatUp: NSTextField?
    private var floatMeta: NSTextField?
    private var floatDownUnit: NSTextField?
    private var floatUpUnit: NSTextField?
    private var spark: SparklineView?

    override init() {
        super.init()
        statusItem.button?.title = "F50 …"
        rebuildMenu()
        refreshLoginState()
        refreshStatusTitle()
        startTimer()
    }

    // MARK: 菜单

    private func rebuildMenu() {
        statusItem.button?.toolTip = S.tooltip
        let menu = NSMenu()

        headerItem = NSMenuItem(title: S.connecting, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        intervalMenu = NSMenu()
        for sec in [1, 2, 5] {
            let it = NSMenuItem(title: S.sec(sec), action: #selector(setInterval(_:)), keyEquivalent: "")
            it.target = self
            it.tag = sec
            it.state = TimeInterval(sec) == interval ? .on : .off
            intervalMenu.addItem(it)
        }
        let intervalParent = NSMenuItem(title: S.refreshInterval, action: nil, keyEquivalent: "")
        intervalParent.submenu = intervalMenu
        menu.addItem(intervalParent)

        unitMenu = NSMenu()
        for (title, key) in [(S.unitBits, "bits"), (S.unitBytes, "bytes")] {
            let it = NSMenuItem(title: title, action: #selector(setUnit(_:)), keyEquivalent: "")
            it.target = self
            it.tag = key == "bits" ? 0 : 1
            it.state = speedUnit == key ? .on : .off
            unitMenu.addItem(it)
        }
        let unitParent = NSMenuItem(title: S.speedUnitMenu, action: nil, keyEquivalent: "")
        unitParent.submenu = unitMenu
        menu.addItem(unitParent)

        let layoutSub = NSMenu()
        for (title, key) in [(S.layoutVertical, "vertical"), (S.layoutHorizontal, "horizontal")] {
            let it = NSMenuItem(title: title, action: #selector(setLayout(_:)), keyEquivalent: "")
            it.target = self
            it.tag = key == "vertical" ? 0 : 1
            it.state = menuLayout == key ? .on : .off
            layoutSub.addItem(it)
        }
        let layoutParent = NSMenuItem(title: S.layoutMenu, action: nil, keyEquivalent: "")
        layoutParent.submenu = layoutSub
        menu.addItem(layoutParent)

        floatItem = NSMenuItem(title: S.showFloat, action: #selector(toggleFloat), keyEquivalent: "")
        floatItem.target = self
        floatItem.state = panel != nil ? .on : .off
        menu.addItem(floatItem)

        loginItem = NSMenuItem(title: S.launchAtLogin, action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let langMenu = NSMenu()
        for (code, name) in [("zh", "中文"), ("en", "English")] {
            let it = NSMenuItem(title: name, action: #selector(setLang(_:)), keyEquivalent: "")
            it.target = self
            it.tag = code == "zh" ? 0 : 1
            it.state = lang == code ? .on : .off
            langMenu.addItem(it)
        }
        let langParent = NSMenuItem(title: S.language, action: nil, keyEquivalent: "")
        langParent.submenu = langMenu
        menu.addItem(langParent)
        menu.addItem(.separator())

        let openWeb = NSMenuItem(title: S.openAdmin, action: #selector(openWebPage), keyEquivalent: "")
        openWeb.target = self
        menu.addItem(openWeb)

        let quit = NSMenuItem(title: S.quit, action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        refreshHeader()
    }

    @objc private func setLang(_ sender: NSMenuItem) {
        lang = sender.tag == 0 ? "zh" : "en"
        rebuildMenu()
        updateFloat()
    }

    @objc private func setUnit(_ sender: NSMenuItem) {
        speedUnit = sender.tag == 0 ? "bits" : "bytes"
        if let submenu = sender.menu {
            for it in submenu.items { it.state = (it == sender) ? .on : .off }
        }
        refreshStatusTitle()
        updateFloat()
    }

    @objc private func setLayout(_ sender: NSMenuItem) {
        menuLayout = sender.tag == 0 ? "vertical" : "horizontal"
        if let submenu = sender.menu {
            for it in submenu.items { it.state = (it == sender) ? .on : .off }
        }
        refreshStatusTitle()
    }

    private func refreshHeader() {
        if let up = latestUp, let down = latestDown {
            headerItem.title = latestMeta.isEmpty ? "▼\(formatSpeedCompact(down, bytes: false)) ▲\(formatSpeedCompact(up, bytes: false))" : latestMeta
        } else {
            headerItem.title = S.unreachable("192.168.0.1 / en0")
        }
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        interval = TimeInterval(sender.tag)
        for it in intervalMenu.items { it.state = (it.tag == sender.tag) ? .on : .off }
        startTimer()
    }

    @objc private func toggleFloat() {
        if panel != nil {
            panel?.close(); panel = nil
            floatItem.state = .off
        } else {
            createPanel()
            floatItem.state = .on
        }
    }

    /// 启动参数 --float 使用：直接弹出悬浮窗
    func showFloatAtStartup() {
        guard panel == nil else { return }
        createPanel()
        floatItem.state = .on
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch { /* 忽略错误，仅刷新状态显示 */ }
        refreshLoginState()
    }

    private func refreshLoginState() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openWebPage() {
        NSWorkspace.shared.open(webURL)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// 按当前布局偏好刷新菜单栏标题
    private func refreshStatusTitle() {
        guard let button = statusItem.button else { return }
        let bytes = speedUnit == "bytes"
        let text: String
        if let up = latestUp, let down = latestDown {
            if menuLayout == "vertical" {
                text = "▼\(formatSpeedCompact(down, bytes: bytes))\n▲\(formatSpeedCompact(up, bytes: bytes))"
            } else {
                text = "▼\(formatSpeedCompact(down, bytes: bytes)) ▲\(formatSpeedCompact(up, bytes: bytes))"
            }
        } else {
            text = menuLayout == "vertical" ? "▼—\n▲—" : "▼— ▲—"
        }
        // 定宽：按现实最大内容预留，任何速率下位置都稳定
        statusItem.length = menuLayout == "vertical" ? widthVertical : widthHorizontal
        button.image = statusImage(title: text)
        button.title = ""
        button.imagePosition = .imageOnly
    }

    /// 菜单栏数字字体（加粗等宽）
    private let statusFontSize: CGFloat = 10
    private func statusFont(scale: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: statusFontSize * scale, weight: .semibold)
    }

    /// 定宽基准：两位整数 + 小数 + 单位，覆盖 99.9MB/s 以内及 Gbps 级显示
    private func fixedWidth(_ refs: [String]) -> CGFloat {
        refs.map { measureWidth($0) }.max()! + 4
    }
    private lazy var widthVertical: CGFloat = fixedWidth(["▼99.9M\n▲99.9M", "▼99.9MB\n▲99.9MB"])
    private lazy var widthHorizontal: CGFloat = fixedWidth(["▼99.9M ▲99.9M", "▼99.9MB ▲99.9MB"])

    /// 测量指定文本在状态栏图片中的逻辑宽度（pt）
    private func measureWidth(_ text: String) -> CGFloat {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let ps = NSMutableParagraphStyle()
        ps.alignment = .left
        let attr = NSAttributedString(string: text, attributes: [.font: statusFont(scale: scale), .paragraphStyle: ps])
        let b = attr.boundingRect(with: NSSize(width: 1000 * scale, height: 100 * scale), options: [.usesLineFragmentOrigin])
        return b.width / scale
    }

    /// 状态栏文字颜色：以菜单栏按钮的实际外观为准，纯色不透明（模板着色会发淡）
    private func statusTextColor() -> NSColor {
        let appearance = statusItem.button?.effectiveAppearance ?? NSAppearance.currentDrawing()
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark ? NSColor.white : NSColor.black
    }

    /// 把文字渲染成固定位图（与菜单栏同高），垂直居中由绘制坐标精确控制。
    /// 两种布局都走这条路径，保证颜色、字重完全一致。
    private func statusImage(title: String) -> NSImage {
        let thickness = NSStatusBar.system.thickness
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let width = menuLayout == "vertical" ? widthVertical : widthHorizontal
        let ps = NSMutableParagraphStyle()
        ps.alignment = menuLayout == "vertical" ? .left : .center
        ps.lineHeightMultiple = 0.92
        ps.paragraphSpacing = 0
        ps.paragraphSpacingBefore = 0
        let attrs: [NSAttributedString.Key: Any] = [
            .font: statusFont(scale: scale),
            .paragraphStyle: ps,
            .foregroundColor: statusTextColor(),
        ]
        let attr = NSAttributedString(string: title, attributes: attrs)
        let textBounds = attr.boundingRect(with: NSSize(width: (width - 2) * scale, height: thickness * 4 * scale),
                                           options: [.usesLineFragmentOrigin])
        let pxW = width * scale
        let pxH = thickness * scale
        let image = NSImage(size: NSSize(width: pxW, height: pxH))
        image.lockFocus()
        let y = max(0, (pxH - textBounds.height) / 2)
        attr.draw(with: NSRect(x: scale, y: y, width: (width - 2) * scale, height: textBounds.height),
                  options: [.usesLineFragmentOrigin], context: nil)
        image.unlockFocus()
        image.size = NSSize(width: width, height: thickness)
        return image
    }

    // MARK: 悬浮窗

    private func arrowLabel(_ s: String, _ c: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 18, weight: .medium)
        l.textColor = c
        return l
    }

    private func valueLabel() -> NSTextField {
        let l = NSTextField(labelWithString: "–")
        l.font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .medium)
        return l
    }

    private func unitLabel() -> NSTextField {
        let l = NSTextField(labelWithString: "Mbps")
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func createPanel() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 250, height: 168),
                        styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.title = S.panelTitle
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary]
        p.contentView?.wantsLayer = true
        p.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        p.contentView?.layer?.cornerRadius = 12
        p.contentView?.layer?.borderWidth = 0.5
        p.contentView?.layer?.borderColor = NSColor.separatorColor.cgColor

        let downVal = valueLabel()
        let downUnit = unitLabel()
        let downRow = NSStackView(views: [arrowLabel("▼", .systemBlue), downVal, downUnit, NSView()])
        downRow.orientation = .horizontal
        downRow.alignment = .centerY
        downRow.spacing = 6
        downRow.distribution = .gravityAreas

        let upVal = valueLabel()
        let upUnit = unitLabel()
        let upRow = NSStackView(views: [arrowLabel("▲", .systemOrange), upVal, upUnit, NSView()])
        upRow.orientation = .horizontal
        upRow.alignment = .centerY
        upRow.spacing = 6
        upRow.distribution = .gravityAreas

        let rates = NSStackView(views: [downRow, upRow])
        rates.orientation = .vertical
        rates.alignment = .leading
        rates.spacing = 6
        rates.translatesAutoresizingMaskIntoConstraints = false
        rates.widthAnchor.constraint(equalToConstant: 218).isActive = true

        let spark = SparklineView()
        spark.translatesAutoresizingMaskIntoConstraints = false
        spark.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let meta = NSTextField(labelWithString: "")
        meta.font = .systemFont(ofSize: 11)
        meta.textColor = .secondaryLabelColor
        meta.alignment = .center
        meta.translatesAutoresizingMaskIntoConstraints = false
        meta.widthAnchor.constraint(equalToConstant: 218).isActive = true

        let stack = NSStackView(views: [rates, spark, meta])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        p.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: p.contentView!.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: p.contentView!.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: p.contentView!.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: p.contentView!.bottomAnchor, constant: -12),
        ])
        self.panel = p
        self.floatDown = downVal
        self.floatUp = upVal
        self.floatMeta = meta
        self.floatDownUnit = downUnit
        self.floatUpUnit = upUnit
        self.spark = spark
        p.center()
        p.orderFrontRegardless()
        updateFloat()
    }

    private func updateFloat() {
        guard panel != nil else { return }
        let bytes = speedUnit == "bytes"
        if let up = latestUp, let down = latestDown {
            let d = formatSpeed(down, bytes: bytes)
            let u = formatSpeed(up, bytes: bytes)
            floatDown?.stringValue = d.0
            floatUp?.stringValue = u.0
            floatDownUnit?.stringValue = d.1
            floatUpUnit?.stringValue = u.1
            floatMeta?.stringValue = latestMeta
        } else {
            floatDown?.stringValue = "–"
            floatUp?.stringValue = "–"
            floatMeta?.stringValue = S.unreachable("192.168.0.1 / en0")
        }
        spark?.history = history
    }

    // MARK: 轮询

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    private func applySample(up: Double, down: Double, meta: String) {
        latestUp = up
        latestDown = down
        latestMeta = meta
        history.append(Sample(up: up, down: down))
        if history.count > 180 { history.removeFirst(history.count - 180) }
        refreshStatusTitle()
        refreshHeader()
        updateFloat()
    }

    @objc private func poll() {
        guard !fetching else { return }
        fetching = true
        fetchRouter { [weak self] info in
            guard let self = self else { return }
            if let info = info {
                DispatchQueue.main.async {
                    self.fetching = false
                    self.applySample(up: info.up, down: info.down, meta: S.meta(info.network, info.signal, info.staNum))
                }
            } else {
                // F50 不可达：回退到本机 en0 网卡计数
                DispatchQueue.global(qos: .utility).async {
                    let now = Date.timeIntervalSinceReferenceDate
                    var up: Double = 0, down: Double = 0
                    let iface = primaryInterface()
                    if let cur = readNetCounters(interface: iface) {
                        if let last = self.lastCounter {
                            let dt = now - last.t
                            if dt > 0 {
                                down = Double(cur.ibytes &- last.ibytes) * 8 / dt
                                up = Double(cur.obytes &- last.obytes) * 8 / dt
                            }
                        }
                        self.lastCounter = NetCounterSample(ibytes: cur.ibytes, obytes: cur.obytes, t: now)
                    }
                    let ssid = currentWiFiSSID()
                    DispatchQueue.main.async {
                        self.fetching = false
                        self.applySample(up: max(up, 0), down: max(down, 0), meta: S.localMeta(ssid, iface))
                    }
                }
            }
        }
    }
}

// MARK: - 探针模式

if CommandLine.arguments.contains("--probe") {
    let sem = DispatchSemaphore(value: 0)
    fetchRouter { info in
        if let info = info {
            print("ROUTER OK down=\(info.down) up=\(info.up) net=\(info.network) sig=\(info.signal) sta=\(info.staNum)")
        } else {
            print("ROUTER FAIL")
        }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 8)
    let iface = primaryInterface()
    if let c = readNetCounters(interface: iface) {
        print("IFACE=\(iface) ibytes=\(c.ibytes) obytes=\(c.obytes)")
    }
    print("SSID=\(currentWiFiSSID())")
    exit(0)
}

/// 本机速率回退路径验证：采样两次（间隔 2 秒）计算 bps
if CommandLine.arguments.contains("--probe-local") {
    let iface = primaryInterface()
    guard let c1 = readNetCounters(interface: iface) else { print("NO COUNTER"); exit(1) }
    let t1 = Date.timeIntervalSinceReferenceDate
    Thread.sleep(forTimeInterval: 2)
    guard let c2 = readNetCounters(interface: iface) else { print("NO COUNTER"); exit(1) }
    let t2 = Date.timeIntervalSinceReferenceDate
    let down = Double(c2.ibytes &- c1.ibytes) * 8 / (t2 - t1)
    let up = Double(c2.obytes &- c1.obytes) * 8 / (t2 - t1)
    print("IFACE=\(iface) LOCAL down=\(down)bps up=\(up)bps")
    exit(0)
}

// MARK: - 启动

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = F50Controller()
// 启动参数 --float：直接打开悬浮窗（用于调试与默认展示）
if CommandLine.arguments.contains("--float") {
    controller.showFloatAtStartup()
}
app.run()
