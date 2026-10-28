import Cocoa

/// 给我们的菜单项画彩色图标，和 Finder 原生菜单项（单色模板图标）一眼区分开。
///
/// Finder 会跨进程复制扩展返回的菜单：富文本标题、文字颜色都会被丢掉，只有 `image` 能保留。
/// 所以把 SF Symbol 按分组颜色画进普通位图（`isTemplate = false`），系统就不会再把它染成单色。
enum MenuIcons {

    private static let side: CGFloat = 16

    static func symbol(_ name: String, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        return rasterize(image)
    }

    /// 「打开方式」里的 App 直接用它自己的图标。
    static func appIcon(atPath path: String) -> NSImage? {
        rasterize(NSWorkspace.shared.icon(forFile: path))
    }

    /// 画进 16pt@2x 的位图并居中。位图在跨进程序列化时最稳，颜色也原样保留。
    private static func rasterize(_ image: NSImage) -> NSImage? {
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(side * scale), pixelsHigh: Int(side * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: side, height: side)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = image.size
        let ratio = min(side / max(s.width, 1), side / max(s.height, 1), 1)   // 只缩小不放大
        let w = s.width * ratio, h = s.height * ratio
        image.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()

        let out = NSImage(size: rep.size)
        out.addRepresentation(rep)
        out.isTemplate = false
        return out
    }
}
