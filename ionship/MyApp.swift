import IonshipCore
import SwiftUI

@main struct IonshipApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 960, minHeight: 640)
                .task { model.start() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if showsWordmarkBar {
                HStack {
                    Wordmark()
                    Spacer()
                    if case .connect = model.phase {
                        Text("STEP 1 OF 2").font(Theme.mono(11)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 20)
                .frame(height: 56)
                Divider().overlay(Theme.hairline)
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.ground)
        .preferredColorScheme(.light)
    }

    /// The main window and the chooser draw their own headers.
    private var showsWordmarkBar: Bool {
        switch model.phase {
        case .choose, .health: false
        default: true
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .checking, .loading:
            ProgressView()
        case .connect(let access):
            ConnectView(access: access)
        case .choose:
            ChooseView(model: model)
        case .analyzing:
            VStack(spacing: 10) {
                ProgressView()
                Text("Reading \(model.picker.selectedMessageCount.formatted()) messages…").foregroundStyle(Theme.secondary)
            }
        case .health:
            MainView(model: model)
        case .failed(let message):
            Text(message).foregroundStyle(Theme.secondary).padding()
        }
    }
}
