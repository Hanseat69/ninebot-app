import SwiftUI

@main
struct NinebotAppApp: App {
    // Wird beim App-Start erzeugt, auch wenn iOS die App nur im Hintergrund
    // startet (z. B. weil sich der gemerkte Scooter meldet).
    private let model = ScooterModel.shared
    private let documents = DocumentStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if let screen = DemoMode.screen {
            DemoData.load(screen: screen, model: model, documents: documents)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            root
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.maintenance)
                .environmentObject(documents)
        }
        .onChange(of: scenePhase) { phase in
            guard !DemoMode.isActive else { return }
            switch phase {
            case .active:
                documents.reload()
                model.appDidBecomeActive()
            case .background:
                documents.lock()   // Dokumente beim Verlassen der App wieder sperren
            default:
                break
            }
        }
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
        if let screen = DemoMode.screen {
            DemoRootView(screen: screen)
        } else {
            MainTabView()
        }
        #else
        MainTabView()
        #endif
    }
}
