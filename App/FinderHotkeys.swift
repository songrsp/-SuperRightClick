import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Finder 里的 Windows 式快捷键：⌘X 剪切、⌘V 粘贴(移动)、Delete 删除、回车打开、F2 重命名。
///
/// Finder Sync 扩展收不到键盘事件，所以由常驻后台的主程序装一个 CGEventTap。
/// 只在 Finder 位于前台、且焦点不在文本框（重命名 / 搜索栏）或对话框时接管，
/// 并且只是把按键改写成 Finder 自己的等价快捷键 —— 搬文件仍由 Finder 完成，
/// 进度条、同名冲突提示、撤销(⌘Z)都是原生的。
///
/// 需要「辅助功能」权限；没授权时定时重试，用户授权后无需重启本程序即可生效。
final class FinderHotkeys {

    static let shared = FinderHotkeys()

    /// 自己合成的按键打上这个标记，回调里直接放行，避免被再次改写。
    private static let syntheticMarker: Int64 = 0x5352_434B   // "SRCK"
    private static let finderBundleID = "com.apple.finder"

    private var tap: CFMachPort?
    private var retryTimer: Timer?

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 弹出系统的辅助功能授权提示（已授权时无动作）。
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    func start() {
        guard tap == nil, !installTap(), retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            guard let self = self, self.installTap() else { return }
            timer.invalidate()
            self.retryTimer = nil
        }
    }

    private func installTap() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: Self.callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Log.error("创建键盘监听失败")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        Log.info("Finder 快捷键已启用")
        return true
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
        let hotkeys = Unmanaged<FinderHotkeys>.fromOpaque(userInfo).takeUnretainedValue()
        return hotkeys.handle(type, event)
    }

    // MARK: - 按键分发

    private enum Shortcut {
        case cut, paste, delete, open, rename

        init?(_ event: CGEvent) {
            // fn 不参与匹配：笔记本上 fn+⌫ = 向前删除，fn+F2 = F2。
            let mods = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
            switch (Int(event.getIntegerValueField(.keyboardEventKeycode)), mods) {
            case (kVK_ANSI_X, .maskCommand):                     self = .cut
            case (kVK_ANSI_V, .maskCommand):                     self = .paste
            case (kVK_Delete, []), (kVK_ForwardDelete, []):      self = .delete
            case (kVK_Return, []), (kVK_ANSI_KeypadEnter, []):   self = .open
            case (kVK_F2, []):                                   self = .rename
            default: return nil
            }
        }

        var isEnabled: Bool {
            switch self {
            case .cut, .paste:   return Pref.hotkeyCutPaste
            case .delete:        return Pref.hotkeyDelete
            case .open, .rename: return Pref.hotkeyEnterOpen
            }
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker,
              let finder = NSWorkspace.shared.frontmostApplication,
              finder.bundleIdentifier == Self.finderBundleID,
              let shortcut = Shortcut(event), shortcut.isEnabled,
              Self.isBrowsingFiles(pid: finder.processIdentifier) else { return pass }

        // 按住不放时只执行一次，避免连续剪切 / 连续删除。
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        switch shortcut {
        case .cut:
            if !isRepeat { cut() }
        case .paste:
            // 普通复制的内容交给 Finder 原生 ⌘V，不接管。
            guard FileClipboard.isPendingCut else { return pass }
            if !isRepeat { pasteMove() }
        case .delete:
            if !isRepeat { send(kVK_Delete, .maskCommand) }   // Finder 的「移到废纸篓」
        case .open:
            send(kVK_ANSI_O, .maskCommand)
        case .rename:
            send(kVK_Return, [])                              // Finder 里回车 = 重命名
        }
        Log.debugFile("hotkey \(shortcut) repeat=\(isRepeat)")
        return nil
    }

    /// ⌘X：让 Finder 用原生 ⌘C 把选中文件写上剪贴板，再把这份内容标记为「剪切」。
    /// 什么都没选中时剪贴板不会变化，也就不会被标记。
    private func cut() {
        let before = NSPasteboard.general.changeCount
        send(kVK_ANSI_C, .maskCommand)
        whenPasteboardChanges(since: before, attempts: 20) {
            FileClipboard.markSystemPasteboardAsCut()
        }
    }

    /// ⌘V 且剪贴板是剪切内容：改发 ⌥⌘V（Finder 原生「将项目移到这里」）。
    private func pasteMove() {
        let count = NSPasteboard.general.changeCount
        send(kVK_ANSI_V, [.maskCommand, .maskAlternate])
        // 剪切只能粘贴一次：等 Finder 读完剪贴板再清空，避免第二次 ⌘V 去搬已不存在的源文件。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if NSPasteboard.general.changeCount == count { FileClipboard.clear() }
        }
    }

    private func whenPasteboardChanges(since count: Int, attempts: Int, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            if NSPasteboard.general.changeCount != count {
                action()
            } else if attempts > 1 {
                self?.whenPasteboardChanges(since: count, attempts: attempts - 1, action)
            }
        }
    }

    /// 合成一次完整按键（按下 + 抬起），发给当前前台的 Finder。
    private func send(_ key: Int, _ flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            e.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: - 焦点判断

    /// 焦点在文本框（重命名、搜索栏、前往文件夹）或对话框 / 弹出面板里时不接管，保持系统原样。
    private static func isBrowsingFiles(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        // 回调运行在键盘事件链上，Finder 卡顿时不能拖住全局输入。
        AXUIElementSetMessagingTimeout(app, 0.2)

        if let focused: AXUIElement = attribute(app, kAXFocusedUIElementAttribute),
           let role: String = attribute(focused, kAXRoleAttribute),
           [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) {
            return false
        }
        // 桌面没有焦点窗口，视为在浏览文件。
        guard let window: AXUIElement = attribute(app, kAXFocusedWindowAttribute) else { return true }
        if let subrole: String = attribute(window, kAXSubroleAttribute),
           subrole != kAXStandardWindowSubrole {
            return false
        }
        let children: [AXUIElement] = attribute(window, kAXChildrenAttribute) ?? []
        return !children.contains { (attribute($0, kAXRoleAttribute) as String?) == kAXSheetRole }
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
