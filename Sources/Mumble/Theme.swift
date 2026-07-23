import SwiftUI
import CoreText

/// Mumble design system tokens (from the design handoff): navy brand, pink
/// reserved exclusively for the live/recording state, HUD Ink for the overlay,
/// and Goodly only for big display headings and oversized stat numbers.
enum Theme {
    // Colours
    static let navy = Color(red: 0x1D/255, green: 0x3A/255, blue: 0x66/255)       // brand/primary
    static let navyPressed = Color(red: 0x10/255, green: 0x25/255, blue: 0x4D/255)
    static let navyWash = Color(red: 0xEA/255, green: 0xF0/255, blue: 0xF9/255)   // active sidebar bg
    static let pink = Color(red: 0xDF/255, green: 0x6C/255, blue: 0xB4/255)       // live state ONLY
    static let pinkTint = Color(red: 0xFA/255, green: 0xED/255, blue: 0xF5/255)
    static let pinkTintText = Color(red: 0xC7/255, green: 0x4E/255, blue: 0x9C/255)
    static let hudInk = Color(red: 0x2D/255, green: 0x31/255, blue: 0x42/255)     // HUD surfaces only
    static let ink = Color(red: 0x1D/255, green: 0x1D/255, blue: 0x1F/255)        // primary text
    static let grey = Color(red: 0x6E/255, green: 0x6E/255, blue: 0x73/255)       // secondary text
    static let surface = Color(red: 0xF8/255, green: 0xF8/255, blue: 0xF8/255)    // wells, stat cards

    // Goodly — display headings and stat numbers only, never body/controls.
    static func display(_ size: CGFloat = 28) -> Font { .custom("GoodlySemibold", size: size) }
    static func heading(_ size: CGFloat = 20) -> Font { .custom("GoodlySemibold", size: size) }
    static func statNumber(_ size: CGFloat = 30) -> Font { .custom("GoodlyLight", size: size) }

    /// Register bundled Goodly OTFs (process-scoped). Call once at launch.
    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts") else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "otf" } ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// The two-tone square mark used in in-app chrome (matches the app icon).
    static var logoMark: NSImage? {
        Bundle.main.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent("logo-alternate.png")) }
    }
}
