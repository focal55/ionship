import IonshipCore
import SwiftUI

struct ConnectView: View {
    let access: MessagesAccess
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Let ionship read your Messages history")
                        .font(.system(size: 40, weight: .semibold))
                        .tracking(-1.2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("macOS keeps Messages locked behind Full Disk Access. Turn it on once and ionship can see your conversations as they happen.")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: 480, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 14) {
                    promise("Read-only", "ionship never edits, deletes or sends from your history.")
                    promise("Stays on this Mac", "Analysis and memory run on-device unless you turn on a cloud model.")
                    promise("Only Messages", "ionship reads the Messages database and nothing else on your disk.")
                }

                HStack(spacing: 14) {
                    Button("Open System Settings") { openURL(MessagesAccess.settingsURL) }
                        .buttonStyle(PrimaryButtonStyle())
                    status
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    step("01", "Open System Settings › Privacy & Security › Full Disk Access")
                step("02", "Switch on ionship, or drag it into the list")
                step("03", "Come back here — no restart needed")
                }
                settingsIllustration
                Text("Read-only. Revoke any time from the same screen; ionship stops reading immediately.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Text("Already switched on? An older copy of ionship may be listed under the same name. Turn on the one that’s off, or remove both with – and add ionship again.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 440, alignment: .leading)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 72)
        .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var status: some View {
        switch access {
        case .unavailable:
            Label("No Messages database found on this Mac", systemImage: "exclamationmark.circle")
                .foregroundStyle(Theme.secondary)
        default:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for access — this screen updates on its own")
            }
            .foregroundStyle(Theme.secondary)
        }
    }

    /// A picture of the System Settings pane, not a control.
    private var settingsIllustration: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Privacy & Security")
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                Text("Full Disk Access").foregroundStyle(Theme.ink).fontWeight(.medium)
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 14)
            Divider().overlay(Color(red: 0.937, green: 0.937, blue: 0.925))
            illustratedRow("Other app", on: false, highlighted: false)
            illustratedRow("ionship", on: true, highlighted: true)
        }
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
        .shadow(color: .black.opacity(0.06), radius: 16, y: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Illustration: ionship switched on in Full Disk Access")
    }

    private func illustratedRow(_ name: String, on: Bool, highlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Text(String(name.prefix(1)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(highlighted ? .white : Theme.secondary)
                .frame(width: 26, height: 26)
                .background(highlighted ? Theme.ink : Color(red: 0.914, green: 0.914, blue: 0.898), in: .rect(cornerRadius: 7))
            Text(name).font(.system(size: 14))
            Spacer()
            Capsule()
                .fill(on ? Theme.accent : Color(red: 0.851, green: 0.851, blue: 0.831))
                .frame(width: 34, height: 20)
                .overlay(alignment: on ? .trailing : .leading) { Circle().fill(.white).frame(width: 16, height: 16).padding(2) }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(highlighted ? Theme.accentWash : .clear)
        .overlay(highlighted ? RoundedRectangle(cornerRadius: 0).stroke(Theme.accent, lineWidth: 1.5) : nil)
    }

    private func promise(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.positive)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number).font(Theme.mono(11)).foregroundStyle(Theme.accent)
            Text(text).font(.system(size: 14))
        }
    }
}

#Preview {
    ConnectView(access: .denied)
        .frame(width: 1280, height: 800)
        .background(Theme.ground)
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(.light)
}
