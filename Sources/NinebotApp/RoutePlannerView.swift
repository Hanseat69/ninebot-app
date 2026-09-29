//
//  RoutePlannerView.swift
//  Tab „Route“: Favoriten, Reichweitenkreis, Zielsuche, Route mit
//  Reichweitenprüfung, Navigation in der App und Rückweg zum Start.
//
//  Fahrradrouten liefert MapKit einer App erst ab iOS 26. Auf älteren Geräten
//  wird ersatzweise eine Fußgängerroute berechnet; Apple Maps selbst navigiert
//  in Deutschland mit Fahrradrouten.
//

import SwiftUI
import MapKit
import CoreLocation

struct RoutePlannerView: View {
    @EnvironmentObject private var model: ScooterModel
    @StateObject private var planner = RoutePlanner()
    @StateObject private var favorites = FavoritePlaces()
    @State private var favoriteName = ""
    @State private var askingFavoriteName = false
    var demoQuery: String? = nil
    var demoStartNavigation = false

    init(demoQuery: String? = nil, demoStartNavigation: Bool = false) {
        self.demoQuery = demoQuery
        self.demoStartNavigation = demoStartNavigation
    }

    var body: some View {
        NavigationStack {
            List {
                searchSection

                if let error = planner.error {
                    Section { Text(error).foregroundColor(.secondary) }
                }

                if let route = planner.route, let destination = planner.destination {
                    routeSections(route: route, destination: destination)
                } else if planner.results.isEmpty {
                    favoritesSection
                    returnSection
                    rangeSection
                }
            }
            .navigationTitle("Route")
            .onAppear {
                planner.locate()
                #if DEBUG
                if DemoMode.isActive { favorites.loadDemo() }
                #endif
                if let query = demoQuery, planner.route == nil {
                    planner.query = query
                    planner.search(selectFirst: true)
                }
            }
            .onChange(of: planner.route) { route in
                if demoStartNavigation, route != nil, planner.activeNavigation == nil {
                    planner.startNavigation()
                }
            }
            .fullScreenCover(item: $planner.activeNavigation) { nav in
                NavigationScreen(nav: nav, onReturnTrip: { planner.startReturnTrip() },
                                 onClose: { planner.endNavigation() })
                    .environmentObject(model)
            }
            .alert("Favorit speichern", isPresented: $askingFavoriteName) {
                TextField("Name", text: $favoriteName)
                Button("Sichern") {
                    let name = favoriteName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty, let item = planner.destination { favorites.save(name: name, item: item) }
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    // MARK: - Suche

    private var searchSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Ziel suchen", text: $planner.query)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { planner.search() }
                if planner.route != nil || !planner.results.isEmpty {
                    Button {
                        planner.reset()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if planner.isSearching { ProgressView() }
            ForEach(planner.results, id: \.self) { item in
                Button {
                    planner.select(item)
                } label: {
                    VStack(alignment: .leading) {
                        Text(item.name ?? "Ziel").foregroundColor(.primary)
                        if let address = item.placemark.title {
                            Text(address).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Ohne Ziel: Favoriten, Rückweg, Reichweite

    private var favoritesSection: some View {
        Section {
            if favorites.places.isEmpty {
                Text("Noch keine Favoriten. Ziel suchen und „Als Favorit speichern“ tippen — zum Beispiel für Zuhause oder die Arbeit.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            ForEach(favorites.places) { place in
                Button {
                    planner.select(place.mapItem)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: place.symbol)
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(place.name == "Zuhause" ? Color.blue
                                                      : (place.name == "Arbeit" ? Color.brown : Color.orange)))
                        VStack(alignment: .leading) {
                            Text(place.name).foregroundColor(.primary)
                            Text(place.address).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }
                .swipeActions {
                    Button("Löschen", role: .destructive) { favorites.delete(place) }
                }
            }
        } header: {
            Text("Favoriten")
        }
    }

    @ViewBuilder private var returnSection: some View {
        if let origin = planner.returnTarget {
            Section {
                Button {
                    planner.select(origin)
                } label: {
                    Label("Zurück zum Startpunkt", systemImage: "arrow.uturn.backward.circle.fill")
                }
            } footer: {
                Text("Startpunkt deiner letzten Navigation.")
            }
        }
    }

    @ViewBuilder private var rangeSection: some View {
        Section {
            if let range = model.remainingRangeKm, let here = planner.currentLocation {
                let usable = usableRange(range)
                RangeMapView(center: here.coordinate, usableRangeKm: usable)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
                HStack(spacing: 16) {
                    legend(color: .green, text: "Hin und zurück")
                    legend(color: .orange, text: "Nur hin")
                }
                .font(.caption)
                ValueRow(title: "Restreichweite laut Scooter", value: Format.kilometers(range))
            } else if model.remainingRangeKm == nil {
                Text("Die Reichweite erscheint, sobald der Scooter einmal verbunden war.")
                    .foregroundColor(.secondary)
            } else {
                Text("Standort wird ermittelt …").foregroundColor(.secondary)
            }
        } header: {
            Text("So weit kommst du")
        } footer: {
            Text("Luftlinie mit Umwegfaktor für echte Straßen. Unter 10 °C rechnet die App mit 20 % weniger Reichweite.")
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().stroke(color, lineWidth: 2).background(Circle().fill(color.opacity(0.15)))
                .frame(width: 12, height: 12)
            Text(text)
        }
    }

    private func usableRange(_ range: Double) -> Double {
        (model.weather?.temperature ?? 20) < 10 ? range * 0.8 : range
    }

    // MARK: - Mit Ziel

    @ViewBuilder
    private func routeSections(route: MKRoute, destination: MKMapItem) -> some View {
        Section {
            RouteMapView(route: route)
                .frame(height: 240)
                .listRowInsets(EdgeInsets())
        }

        Section {
            ValueRow(title: "Ziel", value: destination.name ?? "")
            ValueRow(title: "Strecke", value: Format.kilometers(route.distance / 1000))
            ValueRow(title: "Fahrzeit (ca. 18 km/h)", value: Format.duration(route.distance / 1000 / 18 * 3600))
            if !planner.isCyclingRoute {
                Text("Fußgängerroute als Näherung — Fahrradrouten liefert iOS einer App erst ab iOS 26.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text(planner.isCyclingRoute ? "Fahrradroute" : "Route")
        }

        Section {
            RangeCheck(distanceKm: route.distance / 1000, rangeKm: model.remainingRangeKm, weather: model.weather)
        } header: {
            Text("Reichweite")
        }

        Section {
            Button {
                planner.startNavigation()
            } label: {
                Label("Navigation starten", systemImage: "location.north.line.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            Menu {
                Button("Als Zuhause") { favorites.save(name: "Zuhause", item: destination) }
                Button("Als Arbeit") { favorites.save(name: "Arbeit", item: destination) }
                Button("Eigener Name …") {
                    favoriteName = destination.name ?? ""
                    askingFavoriteName = true
                }
            } label: {
                Label("Als Favorit speichern", systemImage: "star")
            }

            Button {
                planner.openInMaps(destination)
            } label: {
                Label("In Apple Maps öffnen", systemImage: "map")
            }
        } footer: {
            Text("Handy beim Fahren nur in einer festen Halterung nutzen und nicht bedienen.")
        }
    }
}

/// Vergleicht die Strecke mit der Restreichweite des Scooters.
struct RangeCheck: View {
    let distanceKm: Double
    let rangeKm: Double?
    let weather: WeatherInfo?

    var body: some View {
        if let range = rangeKm {
            // Kälte kostet Reichweite: unter 10 °C ziehen wir zur Sicherheit 20 % ab.
            let cold = (weather?.temperature ?? 20) < 10
            let usable = cold ? range * 0.8 : range
            ValueRow(title: "Restreichweite laut Scooter", value: Format.kilometers(range))
            if cold {
                Text("Bei Kälte rechnet die App mit 20 % weniger Reichweite.")
                    .font(.caption).foregroundColor(.secondary)
            }
            if usable >= distanceKm * 2.2 {
                Label("Reicht für Hin- und Rückweg", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if usable >= distanceKm * 1.1 {
                Label("Reicht für den Hinweg, aber nicht sicher zurück", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            } else {
                Label("Reichweite reicht voraussichtlich nicht", systemImage: "xmark.octagon.fill")
                    .foregroundColor(.red)
            }
        } else {
            Text("Restreichweite unbekannt — einmal mit dem Scooter verbinden.")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Logik

final class RoutePlanner: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var query = ""
    @Published private(set) var results: [MKMapItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var destination: MKMapItem?
    @Published private(set) var route: MKRoute?
    @Published private(set) var isCyclingRoute = false
    @Published private(set) var error: String?
    @Published private(set) var currentLocation: CLLocation?
    @Published var activeNavigation: NavigationController?
    /// Startpunkt der letzten Navigation, für den Rückweg.
    @Published private(set) var returnTarget: MKMapItem?

    private var activeSearch: MKLocalSearch?
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    // MARK: Standort

    func locate() {
        switch locationManager.authorizationStatus {
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: locationManager.requestLocation()
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: Suche

    func search(selectFirst: Bool = false) {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        activeSearch?.cancel()
        isSearching = true
        error = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let here = currentLocation {
            request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        let search = MKLocalSearch(request: request)
        activeSearch = search
        search.start { [weak self] response, _ in
            guard let self = self else { return }
            self.isSearching = false
            self.results = response?.mapItems ?? []
            if self.results.isEmpty {
                self.error = "Nichts gefunden."
            } else if selectFirst {
                self.select(self.results[0])
            }
        }
    }

    func reset() {
        query = ""
        results = []
        route = nil
        destination = nil
        error = nil
    }

    func select(_ item: MKMapItem) {
        destination = item
        results = []
        route = nil
        error = nil
        RoutePlanner.calculateRoute(from: MKMapItem.forCurrentLocation(), to: item) { [weak self] route, cycling in
            guard let self = self else { return }
            if let route = route {
                self.route = route
                self.isCyclingRoute = cycling
            } else {
                self.error = "Keine Route gefunden. Ist der Standort erlaubt?"
            }
        }
    }

    /// Fahrradroute ab iOS 26, sonst Fußweg als Näherung.
    static func calculateRoute(from source: MKMapItem, to destination: MKMapItem,
                               completion: @escaping (MKRoute?, Bool) -> Void) {
        func run(_ transport: MKDirectionsTransportType, cycling: Bool, fallback: Bool) {
            let request = MKDirections.Request()
            request.source = source
            request.destination = destination
            request.transportType = transport
            MKDirections(request: request).calculate { response, _ in
                if let route = response?.routes.first {
                    completion(route, cycling)
                } else if fallback {
                    run(.walking, cycling: false, fallback: false)
                } else {
                    completion(nil, false)
                }
            }
        }
        if #available(iOS 26.0, *) {
            run(.cycling, cycling: true, fallback: true)
        } else {
            run(.walking, cycling: false, fallback: false)
        }
    }

    // MARK: Navigation

    func startNavigation() {
        guard let route = route, let destination = destination else { return }
        activeNavigation = NavigationController(route: route, destination: destination,
                                                origin: currentLocation?.coordinate)
    }

    func endNavigation() {
        if let origin = activeNavigation?.origin {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            item.name = "Startpunkt"
            returnTarget = item
        }
        activeNavigation = nil
        reset()
        locate()
    }

    /// Am Ziel: Route zurück zum Startpunkt berechnen und gleich losnavigieren.
    func startReturnTrip() {
        guard let origin = activeNavigation?.origin else { return }
        let start = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        start.name = "Startpunkt"
        let here = activeNavigation?.location.map { MKMapItem(placemark: MKPlacemark(coordinate: $0.coordinate)) }
            ?? MKMapItem.forCurrentLocation()
        let arrivalPoint = activeNavigation?.destination.placemark.coordinate
        activeNavigation = nil
        RoutePlanner.calculateRoute(from: here, to: start) { [weak self] route, cycling in
            guard let self = self, let route = route else {
                self?.error = "Rückweg konnte nicht berechnet werden."
                return
            }
            self.destination = start
            self.route = route
            self.isCyclingRoute = cycling
            // Kurz warten, bis der alte Navigationsbildschirm geschlossen ist.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.activeNavigation = NavigationController(route: route, destination: start, origin: arrivalPoint)
            }
        }
    }

    /// Übergibt das Ziel an Apple Maps, ab iOS 26 direkt im Fahrradmodus.
    func openInMaps(_ item: MKMapItem) {
        if #available(iOS 26.0, *) {
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeCycling])
        } else {
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        }
    }
}

private struct RouteMapView: UIViewRepresentable {
    let route: MKRoute

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        map.addOverlay(route.polyline)
        map.setVisibleMapRect(route.polyline.boundingMapRect,
                              edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30),
                              animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 5
            return renderer
        }
    }
}
