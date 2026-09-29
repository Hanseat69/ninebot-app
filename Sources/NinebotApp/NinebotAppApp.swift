import SwiftUI

@main
struct NinebotAppApp: App {
    // Wird beim App-Start erzeugt, auch wenn iOS die App nur im Hintergrund
    // startet (z. B. weil sich der gemerkte Scooter meldet).
    private let model = ScooterModel.shared
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
            }
            .environmentObject(model)
            .environmentObject(model.store)
            .environmentObject(model.maintenance)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { model.appDidBecomeActive() }
        }
    }
}
