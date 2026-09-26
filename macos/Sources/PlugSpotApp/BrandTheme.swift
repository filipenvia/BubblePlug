import AppKit
import SwiftUI

enum PlugSpotPalette {
    static let canvas = Color(red: 0.025, green: 0.045, blue: 0.10)
    static let card = Color(red: 0.045, green: 0.09, blue: 0.18)
    static let selectedCard = Color(red: 0.055, green: 0.18, blue: 0.31)
    static let chainShelf = Color(red: 0.025, green: 0.065, blue: 0.14)
    static let chainTile = Color(red: 0.06, green: 0.13, blue: 0.24)
    static let cyan = Color(red: 0.20, green: 0.86, blue: 0.98)
    static let blue = Color(red: 0.12, green: 0.43, blue: 0.96)
    static let violet = Color(red: 0.64, green: 0.48, blue: 0.96)
    static let edge = cyan.opacity(0.18)
    static let iridescence = LinearGradient(
        colors: [cyan, blue, violet, Color(red: 0.94, green: 0.60, blue: 0.83), cyan],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let backdrop = LinearGradient(colors: [card, canvas, canvas], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Cache the approved artwork once; opening the bubble does not decode it again.
enum BubblePlugArtwork {
    static let logo: NSImage? = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "BubblePlug", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

struct PlugSpotAudioMark: View {
    var size: CGFloat = 34
    var body: some View {
        Group {
            if let logo = BubblePlugArtwork.logo {
                Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "slider.vertical.3").resizable().scaledToFit()
                    .foregroundStyle(PlugSpotPalette.cyan)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("BubblePlug")
    }
}

struct BubblePlugSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(.dark)
            .tint(PlugSpotPalette.cyan)
            .background(PlugSpotPalette.backdrop)
            .overlay(alignment: .top) {
                Rectangle().fill(PlugSpotPalette.iridescence).frame(height: 1).opacity(0.65)
                    .allowsHitTesting(false)
            }
    }
}
