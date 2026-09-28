import AppKit
import SwiftUI

enum BubblePlugPalette {
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

struct BubblePlugAudioMark: View {
    var size: CGFloat = 34
    var body: some View {
        Group {
            if let logo = BubblePlugArtwork.logo {
                Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "slider.vertical.3").resizable().scaledToFit()
                    .foregroundStyle(BubblePlugPalette.cyan)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("BubblePlug")
    }
}

struct BubbleMonogram: View {
    let initials: String
    let width: CGFloat
    let height: CGFloat

    private var diameter: CGFloat { min(width * 0.78, height * 0.88) }

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [BubblePlugPalette.blue.opacity(0.44), BubblePlugPalette.violet.opacity(0.23), BubblePlugPalette.cyan.opacity(0.12)],
                    center: .init(x: 0.34, y: 0.28), startRadius: 0, endRadius: diameter * 0.7
                ))
                .overlay {
                    Circle().strokeBorder(
                        AngularGradient(colors: [BubblePlugPalette.cyan, .white.opacity(0.9), BubblePlugPalette.violet, BubblePlugPalette.blue, BubblePlugPalette.cyan], center: .center),
                        lineWidth: max(1.5, diameter * 0.055)
                    )
                }
                .overlay(alignment: .topLeading) {
                    Ellipse()
                        .fill(.white.opacity(0.64))
                        .frame(width: diameter * 0.25, height: diameter * 0.08)
                        .rotationEffect(.degrees(-38))
                        .offset(x: diameter * 0.23, y: diameter * 0.13)
                }
                .shadow(color: BubblePlugPalette.cyan.opacity(0.30), radius: diameter * 0.12)
            Text(initials)
                .font(.system(size: diameter * (initials.count > 1 ? 0.38 : 0.46), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .shadow(color: BubblePlugPalette.canvas.opacity(0.8), radius: 2)
        }
        .frame(width: diameter, height: diameter)
        .frame(width: width, height: height)
        .accessibilityLabel(initials)
    }
}

struct BubblePlugSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(.dark)
            .tint(BubblePlugPalette.cyan)
            .background(BubblePlugPalette.backdrop)
            .overlay(alignment: .top) {
                Rectangle().fill(BubblePlugPalette.iridescence).frame(height: 1).opacity(0.65)
                    .allowsHitTesting(false)
            }
    }
}
