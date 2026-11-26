// MouseHighlighter for macOS
// 按下鼠标时在光标处显示半透明光圈，
// 按住拖动时光圈跟随，松开后延时淡出。左键黄色，右键红色。

import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - 配置

enum Config {
    // 可调参数（保存在 UserDefaults，设置窗口里修改）
    struct Adjustable {
        let key: String
        let title: String
        let min: Double
        let max: Double
        let defaultValue: Double
        let step: Double
        let format: (Double) -> String

        var value: Double {
            get { UserDefaults.standard.object(forKey: key) as? Double ?? defaultValue }
            nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
        }
    }

    static let radiusSetting = Adjustable(key: "radius", title: "光圈半径",
                                          min: 8, max: 120, defaultValue: 20, step: 1,
                                          format: { String(format: "%.0f pt", $0) })
    static let fadeDelaySetting = Adjustable(key: "fadeDelay", title: "松开后显示时间",
                                             min: 0, max: 3, defaultValue: 0, step: 0.01,
                                             format: { String(format: "%.2f 秒", $0) })
    static let fadeDurationSetting = Adjustable(key: "fadeDuration", title: "淡出时间",
                                                min: 0.05, max: 3, defaultValue: 0.05, step: 0.01,
                                                format: { String(format: "%.2f 秒", $0) })
    static let all = [radiusSetting, fadeDelaySetting, fadeDurationSetting]

    static var radius: CGFloat { CGFloat(radiusSetting.value) }              // 光圈半径（pt）
    static var fadeDelay: CFTimeInterval { fadeDelaySetting.value }          // 松开后多久开始淡出
    static var fadeDuration: CFTimeInterval { fadeDurationSetting.value }    // 淡出时长

    // 可调颜色（以 "r,g,b,a" 的 sRGB 字符串保存）
    struct ColorSetting {
        let key: String
        let title: String
        let defaultValue: NSColor

        var value: NSColor {
            get {
                guard let str = UserDefaults.standard.string(forKey: key) else { return defaultValue }
                let c = str.split(separator: ",").compactMap { Double($0) }
                guard c.count == 4 else { return defaultValue }
                return NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
            }
            nonmutating set {
                guard let c = newValue.usingColorSpace(.sRGB) else { return }
                let str = [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
                    .map { String(format: "%.4f", Double($0)) }.joined(separator: ",")
                UserDefaults.standard.set(str, forKey: key)
            }
        }
    }

    static let leftColorSetting = ColorSetting(key: "leftColor", title: "左键填充",
                                               defaultValue: NSColor(srgbRed: 1.0, green: 0.85, blue: 0.0, alpha: 0.20))  // 黄色
    static let leftBorderSetting = ColorSetting(key: "leftBorderColor", title: "左键外圈",
                                                defaultValue: NSColor(srgbRed: 1.0, green: 0.85, blue: 0.0, alpha: 0.50))
    static let rightColorSetting = ColorSetting(key: "rightColor", title: "右键填充",
                                                defaultValue: NSColor(srgbRed: 1.0, green: 0.15, blue: 0.15, alpha: 0.30)) // 红色
    static let rightBorderSetting = ColorSetting(key: "rightBorderColor", title: "右键外圈",
                                                 defaultValue: NSColor(srgbRed: 1.0, green: 0.15, blue: 0.15, alpha: 0.50))
    static let colors = [leftColorSetting, leftBorderSetting, rightColorSetting, rightBorderSetting]

    static var leftColor: NSColor { leftColorSetting.value }
    static var rightColor: NSColor { rightColorSetting.value }
    static var leftBorderColor: NSColor { leftBorderSetting.value }
    static var rightBorderColor: NSColor { rightBorderSetting.value }
    static let borderWidth: CGFloat = 2
    static let popDuration: CFTimeInterval = 0.12   // 按下时的放大动画
}

// MARK: - 设置窗口

final class SettingsWindowController: NSWindowController {
    private var rows: [(setting: Config.Adjustable, slider: NSSlider, label: NSTextField)] = []
    private var colorRows: [(setting: Config.ColorSetting, well: NSColorWell, label: NSTextField)] = []

    private static let labelWidth: CGFloat = 110
    private static let sliderWidth: CGFloat = 230
    private static let valueWidth: CGFloat = 64

    init() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Mouse Highlighter 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        // —— 大小与时间 ——
        let sliderGrid = NSGridView()
        sliderGrid.rowSpacing = 12
        sliderGrid.columnSpacing = 12
        for setting in Config.all {
            let slider = NSSlider(value: setting.value, minValue: setting.min, maxValue: setting.max,
                                  target: self, action: #selector(sliderChanged(_:)))
            slider.isContinuous = true
            slider.widthAnchor.constraint(equalToConstant: Self.sliderWidth).isActive = true
            let value = Self.valueLabel(setting.format(setting.value))
            sliderGrid.addRow(with: [Self.rowLabel(setting.title), slider, value])
            rows.append((setting, slider, value))
        }
        Self.styleColumns(of: sliderGrid)

        // —— 颜色：行 = 填充 / 外圈，列 = 左键 / 右键 ——
        let colorGrid = NSGridView()
        colorGrid.rowSpacing = 12
        colorGrid.columnSpacing = 12
        let header = { (text: String) -> NSTextField in
            let l = NSTextField(labelWithString: text)
            l.textColor = .secondaryLabelColor
            return l
        }
        colorGrid.addRow(with: [NSGridCell.emptyContentView, header("左键"), header("右键")])
        let pairs: [(String, Config.ColorSetting, Config.ColorSetting)] = [
            ("填充颜色", Config.leftColorSetting, Config.rightColorSetting),
            ("外圈颜色", Config.leftBorderSetting, Config.rightBorderSetting),
        ]
        for (title, left, right) in pairs {
            colorGrid.addRow(with: [Self.rowLabel(title), colorCell(left), colorCell(right)])
        }
        Self.styleColumns(of: colorGrid)
        // 两个颜色列各占滑块区域的一半，与上方对齐
        let half = (Self.sliderWidth + 12 + Self.valueWidth - 12) / 2
        colorGrid.column(at: 1).width = half
        colorGrid.column(at: 2).width = half
        colorGrid.column(at: 1).xPlacement = .leading
        colorGrid.column(at: 2).xPlacement = .leading

        // —— 底部 ——
        let hint = NSTextField(labelWithString: "调整后点击鼠标即可预览效果")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetDefaults))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bottom = NSStackView(views: [hint, spacer, reset])
        bottom.orientation = .horizontal

        let stack = NSStackView(views: [
            Self.sectionTitle("大小与时间"), sliderGrid, Self.separator(),
            Self.sectionTitle("颜色"), colorGrid, Self.separator(),
            bottom,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(16, after: sliderGrid)
        stack.setCustomSpacing(16, after: colorGrid)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for v in stack.arrangedSubviews where v is NSBox || v === bottom {
            v.widthAnchor.constraint(equalTo: sliderGrid.widthAnchor).isActive = true
        }

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        window.setContentSize(stack.fittingSize)   // 窗口大小正好包住内容，不留空白
        window.center()
    }

    private func colorCell(_ setting: Config.ColorSetting) -> NSView {
        let well = NSColorWell(style: .default)
        well.color = setting.value
        well.target = self
        well.action = #selector(colorChanged(_:))
        well.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let value = Self.valueLabel(Self.opacityText(setting.value))
        value.alignment = .left
        colorRows.append((setting, well, value))
        let cell = NSStackView(views: [well, value])
        cell.orientation = .horizontal
        cell.spacing = 8
        return cell
    }

    private static func rowLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        return l
    }

    private static func valueLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        l.alignment = .right
        l.widthAnchor.constraint(equalToConstant: valueWidth).isActive = true
        return l
    }

    private static func sectionTitle(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return l
    }

    private static func separator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        return b
    }

    private static func styleColumns(of grid: NSGridView) {
        grid.column(at: 0).width = labelWidth
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .none
        for i in 0..<grid.numberOfRows { grid.row(at: i).yPlacement = .center }
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSColorPanel.shared.showsAlpha = true   // 颜色面板里显示不透明度滑块
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let row = rows.first(where: { $0.slider === sender }) else { return }
        let v = (sender.doubleValue / row.setting.step).rounded() * row.setting.step
        row.setting.value = v
        row.label.stringValue = row.setting.format(v)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        guard let row = colorRows.first(where: { $0.well === sender }) else { return }
        row.setting.value = sender.color
        row.label.stringValue = Self.opacityText(sender.color)
    }

    private static func opacityText(_ color: NSColor) -> String {
        String(format: "%.0f%%", Double(color.alphaComponent) * 100)
    }

    @objc private func resetDefaults() {
        for row in rows {
            UserDefaults.standard.removeObject(forKey: row.setting.key)
            row.slider.doubleValue = row.setting.value
            row.label.stringValue = row.setting.format(row.setting.value)
        }
        for row in colorRows {
            UserDefaults.standard.removeObject(forKey: row.setting.key)
            row.well.color = row.setting.value
            row.label.stringValue = Self.opacityText(row.setting.value)
        }
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        colorRows.forEach { $0.well.deactivate() }
        NSColorPanel.shared.close()
    }
}

// MARK: - 覆盖窗口（每个屏幕一个，透明、点击穿透、置顶）

final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setFrame(screen.frame, display: false)

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - 单个光圈

final class Highlight {
    let layer = CAShapeLayer()
    private(set) weak var window: OverlayWindow?

    init(color: NSColor, border: NSColor) {
        let r = Config.radius
        layer.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
        layer.path = CGPath(ellipseIn: layer.bounds.insetBy(dx: Config.borderWidth / 2, dy: Config.borderWidth / 2),
                            transform: nil)
        layer.fillColor = color.cgColor
        layer.strokeColor = border.cgColor
        layer.lineWidth = Config.borderWidth
        // 外发光跟随外圈颜色，外圈越透明发光越弱
        layer.shadowColor = border.withAlphaComponent(1).cgColor
        layer.shadowOpacity = Float(0.8 * border.alphaComponent)
        layer.shadowRadius = 6
        layer.shadowOffset = .zero
    }

    /// 把光圈放到全局坐标 point 处（Cocoa 坐标系，左下角为原点）
    func move(to point: NSPoint, windows: [OverlayWindow]) {
        guard let target = windows.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? window ?? windows.first,
              let host = target.contentView?.layer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if target !== window {
            layer.removeFromSuperlayer()
            layer.contentsScale = target.backingScaleFactor
            host.addSublayer(layer)
            window = target
        }
        layer.position = CGPoint(x: point.x - target.frame.minX, y: point.y - target.frame.minY)
        CATransaction.commit()
    }

    func popIn() {
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = 0.4
        anim.toValue = 1.0
        anim.duration = Config.popDuration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(anim, forKey: "pop")
    }

    func fadeOutAndRemove() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.0
        anim.beginTime = CACurrentMediaTime() + Config.fadeDelay
        anim.duration = Config.fadeDuration
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        let layer = self.layer
        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        layer.add(anim, forKey: "fade")
        CATransaction.commit()
    }
}

// MARK: - 主控制器

final class HighlighterController {
    private var windows: [OverlayWindow] = []
    private var monitors: [Any] = []
    private var leftActive: Highlight?
    private var rightActive: Highlight?

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? start() : stop()
        }
    }

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isEnabled else { return }
            self.rebuildWindows()
        }
    }

    private func start() {
        rebuildWindows()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                           .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                           .mouseMoved]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e) }) {
            monitors.append(g)
        }
        // 点击本 app 自己的菜单栏图标时，全局监听收不到，因此再加一个本地监听
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e); return e }) {
            monitors.append(l)
        }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        leftActive = nil
        rightActive = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let w = OverlayWindow(screen: screen)
            w.orderFrontRegardless()
            return w
        }
    }

    private func handle(_ event: NSEvent) {
        let p = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            leftActive?.fadeOutAndRemove()
            leftActive = press(color: Config.leftColor, border: Config.leftBorderColor, at: p)
        case .rightMouseDown:
            rightActive?.fadeOutAndRemove()
            rightActive = press(color: Config.rightColor, border: Config.rightBorderColor, at: p)
        case .leftMouseDragged, .rightMouseDragged, .mouseMoved:
            leftActive?.move(to: p, windows: windows)
            rightActive?.move(to: p, windows: windows)
        case .leftMouseUp:
            leftActive?.move(to: p, windows: windows)
            leftActive?.fadeOutAndRemove()
            leftActive = nil
        case .rightMouseUp:
            rightActive?.move(to: p, windows: windows)
            rightActive?.fadeOutAndRemove()
            rightActive = nil
        default:
            break
        }
    }

    private func press(color: NSColor, border: NSColor, at p: NSPoint) -> Highlight {
        let h = Highlight(color: color, border: border)
        h.move(to: p, windows: windows)
        h.popIn()
        return h
    }
}

// MARK: - 全局快捷键 ⌃⌥H（Carbon，无需辅助功能权限）

final class HotKey {
    private var ref: EventHotKeyRef?
    private static var action: (() -> Void)?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        HotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4D484C54 /* 'MHLT' */), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}

// MARK: - App / 菜单栏

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = HighlighterController()
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var hotKey: HotKey?
    private var settingsController: SettingsWindowController?
    private var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "启用高亮", action: #selector(toggle), keyEquivalent: "h")
        toggleItem.keyEquivalentModifierMask = [.control, .option]
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let legend = NSMenuItem(title: "左键：黄色  ·  右键：红色", action: nil, keyEquivalent: "")
        legend.isEnabled = false
        menu.addItem(legend)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        loginItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.toggle()
        }

        setEnabled(true)

        // 首次启动时默认开启开机自启
        if !UserDefaults.standard.bool(forKey: "loginItemConfigured") {
            UserDefaults.standard.set(true, forKey: "loginItemConfigured")
            setLoginItem(true)
        }
        refreshLoginItemState()
    }

    // MARK: 开机自启（SMAppService，macOS 13+）

    @objc private func toggleLoginItem() {
        setLoginItem(SMAppService.mainApp.status != .enabled)
        refreshLoginItemState()
    }

    private func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("MouseHighlighter: login item \(on ? "register" : "unregister") failed: \(error)")
        }
        if on && SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func refreshLoginItemState() {
        switch SMAppService.mainApp.status {
        case .enabled:          loginItem.state = .on;    loginItem.title = "开机自动启动"
        case .requiresApproval: loginItem.state = .mixed; loginItem.title = "开机自动启动（需在系统设置中允许）"
        default:                loginItem.state = .off;   loginItem.title = "开机自动启动"
        }
    }

    @objc private func toggle() { setEnabled(!controller.isEnabled) }

    @objc private func openSettings() {
        if settingsController == nil { settingsController = SettingsWindowController() }
        settingsController?.show()
    }

    private func setEnabled(_ on: Bool) {
        controller.isEnabled = on
        toggleItem.state = on ? .on : .off
        let name = on ? "cursorarrow.rays" : "cursorarrow"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Mouse Highlighter")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = !on
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
