import SwiftUI

enum Theme {
    static let ground = Color(red: 0.969, green: 0.969, blue: 0.961)
    static let surface = Color.white
    static let ink = Color(red: 0.067, green: 0.071, blue: 0.078)
    static let secondary = Color(red: 0.361, green: 0.373, blue: 0.392)
    static let muted = Color(red: 0.420, green: 0.431, blue: 0.451)
    static let hairline = Color(red: 0.894, green: 0.894, blue: 0.878)
    static let accent = Color(red: 0.184, green: 0.294, blue: 0.878)
    static let positive = Color(red: 0.059, green: 0.463, blue: 0.431)
    static let accentWash = Color(red: 0.957, green: 0.961, blue: 0.996)
    static let accentBorder = Color(red: 0.855, green: 0.863, blue: 0.969)
    static let warning = Color(red: 0.710, green: 0.235, blue: 0.039)

    static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 44)
            .background(Theme.ink.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: 10))
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: 8))
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 10, height: 10)
            Text("Ode").font(.system(size: 16, weight: .semibold)).tracking(-0.3)
        }
    }
}
