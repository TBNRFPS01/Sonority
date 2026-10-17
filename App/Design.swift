import SwiftUI
import AVKit

enum Palette {
    static let charcoal = Color(red: 0.045, green: 0.065, blue: 0.06)
    static let forest = Color(red: 0.13, green: 0.32, blue: 0.24)
    static let mint = Color(red: 0.72, green: 0.89, blue: 0.72)
    static let burgundy = Color(red: 0.30, green: 0.12, blue: 0.19)
}

struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white.opacity(0.07)))
    }
}
extension View { func panel() -> some View { modifier(Panel()) } }

struct Artwork: View {
    var image: UIImage?
    var radius: CGFloat = 20
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.forest, Palette.charcoal, Palette.burgundy], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "waveform").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(Palette.mint.opacity(0.7)) }
        }.clipShape(RoundedRectangle(cornerRadius: radius)).accessibilityHidden(true)
    }
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(); view.tintColor = .white; view.activeTintColor = .systemGreen
        view.prioritizesVideoDevices = false; return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

func clockTime(_ time: Double) -> String {
    let seconds = Int(max(0, time.isFinite ? time : 0))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

struct SectionHeading: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased()).font(.caption.weight(.semibold)).tracking(3).foregroundStyle(Palette.mint)
            Text(title).font(.system(.largeTitle, design: .serif, weight: .medium))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
}
