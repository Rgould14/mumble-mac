import SwiftUI
import AppKit

/// Mumble design system tokens, adaptive for light + dark. Dark mode: near-black
/// neutral surfaces, white figures, pink as the one accent, a confident blue for
/// chart fills. Pink stays reserved for the live/recording state and accents.
enum Theme {
    /// Build a light/dark adaptive Color that resolves against the effective
    /// appearance (driven app-wide by NSApp.appearance).
    static func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
    private static func hex(_ v: UInt) -> NSColor {
        NSColor(red: CGFloat((v >> 16) & 0xFF)/255, green: CGFloat((v >> 8) & 0xFF)/255,
                blue: CGFloat(v & 0xFF)/255, alpha: 1)
    }

    // Surfaces
    static let surface = dyn(hex(0xF8F8F8), hex(0x1A1B1F))     // stat cards, wells
    static let rowSurface = dyn(hex(0xFFFFFF), hex(0x242529))  // rows inside cards
    static let sidebarSelected = dyn(NSColor.black.withAlphaComponent(0.06),
                                     NSColor.white.withAlphaComponent(0.08))

    // Text
    static let ink = dyn(hex(0x1D1D1F), hex(0xECECEE))         // primary text
    static let grey = dyn(hex(0x6E6E73), hex(0x8B8B92))        // secondary text
    static let figure = dyn(hex(0x1D3A66), hex(0xFFFFFF))      // stat numbers/headline figures

    // Data / brand
    static let navy = dyn(hex(0x1D3A66), hex(0x3E8FD8))        // chart fills, tint
    static let navyWash = dyn(hex(0xEAF0F9), hex(0x22354D))    // chart track
    static let link = dyn(hex(0x1D3A66), hex(0xDF6CB4))        // interactive links

    // Pink — the accent, both modes
    static let pink = Color(red: 0xDF/255, green: 0x6C/255, blue: 0xB4/255)
    static let pinkTint = dyn(hex(0xFAEDF5), hex(0x33202C))
    static let pinkTintText = dyn(hex(0xC74E9C), hex(0xF1A9D5))

    // HUD (floating overlay) — dark in both modes
    static let hudInk = Color(red: 0x2D/255, green: 0x31/255, blue: 0x42/255)

    // Type — all SF Pro
    static func display(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .semibold) }
    static func heading(_ size: CGFloat = 20) -> Font { .system(size: size, weight: .semibold) }
    static func statNumber(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .semibold) }

    static var logoHorizontal: NSImage? {
        Bundle.main.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent("logo-horizontal.png")) }
    }
}

/// App appearance preference; applied app-wide via NSApp.appearance so windows,
/// the HUD panel, and every adaptive Theme colour flip together.
enum Appearance: String, Codable, CaseIterable {
    case system, light, dark

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Whether the effective appearance is dark right now.
    var isDarkNow: Bool {
        switch self {
        case .dark: true
        case .light: false
        case .system:
            NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    static func apply(_ a: Appearance) {
        NSApp.appearance = a.nsAppearance
    }
}
