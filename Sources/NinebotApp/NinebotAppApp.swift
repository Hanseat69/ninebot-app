import SwiftUI

@main
struct NinebotAppApp: App {
    // Wird beim App-Start erzeugt, auch wenn iOS die App nur im Hintergrund
    // startet (z. B. weil sich der gemerkte Scooter meldet).
    private let model = ScooterModel.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                ScooterView()
                    .tabItem { Label("Scooter", systemImage: "scooter") }
                TripListView()
                    .tabItem { Label("Fahrten", systemImage: "map") }
                BatteryView()
                    .tabItem { Label("Akku", systemImage: "battery.75") }
            }
            .environmentObject(model)
            .environmentObject(model.store)
        }
    }
}
