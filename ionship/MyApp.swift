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
            HStack { Wordmark(); Spacer() }
                .padding(.horizontal, 20)
                .frame(height: 52)
            Divider().overlay(Theme.hairline)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.ground)
        .preferredColorScheme(.light)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .checking, .loading:
            ProgressView()
        case .connect(let access):
            ConnectView(access: access)
        case .choose:
            ChooseView(picker: $model.picker, onImport: model.importSelected)
        case .imported(let conversations, let messages):
            VStack(spacing: 8) {
                Text("\(conversations) conversations · \(messages.formatted()) messages").font(.system(size: 22, weight: .semibold))
                Text("Indexing and relationship health come next.").foregroundStyle(Theme.secondary)
            }
        case .failed(let message):
            Text(message).foregroundStyle(Theme.secondary).padding()
        }
    }
}
