import SwiftUI

@main
struct NinebotAppApp: App {
    // Wird beim App-Start erzeugt, auch wenn iOS die App nur im Hintergrund
    // startet (z. B. weil sich der gemerkte Scooter meldet).
    private let model = ScooterModel.shared
    private let documents = DocumentStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                ScooterView()
                    .tabItem { Label("Scooter", systemImage: "scooter") }
                RoutePlannerView()
                    .tabItem { Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond") }
                TripListView()
                    .tabItem { Label("Fahrten", systemImage: "map") }
                BatteryView()
                    .tabItem { Label("Akku", systemImage: "battery.75") }
                HelpView()
                    .tabItem { Label("Hilfe", systemImage: "questionmark.circle") }
            }
            .environmentObject(model)
            .environmentObject(model.store)
            .environmentObject(model.maintenance)
            .environmentObject(documents)
        }
        .onChange(of: scenePhase) { phase in
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
}
