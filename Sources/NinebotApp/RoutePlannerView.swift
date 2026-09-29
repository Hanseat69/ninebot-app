//
//  RoutePlannerView.swift
//  Tab „Route“: Ziel suchen, Route berechnen, mit der Restreichweite des
//  Scooters abgleichen und zur Navigation an Apple Maps (Fahrrad) übergeben.
//
//  Fahrradrouten liefert MapKit einer App erst ab iOS 26. Auf älteren Geräten
//  wird ersatzweise eine Fußgängerroute berechnet; Apple Maps selbst navigiert
//  in Deutschland mit Fahrradrouten.
//

import SwiftUI
import MapKit

struct RoutePlannerView: View {
    @EnvironmentObject private var model: ScooterModel
    @StateObject private var planner = RoutePlanner()
    var demoQuery: String? = nil

    init(demoQuery: String? = nil) {
        self.demoQuery = demoQuery
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Ziel suchen", text: $planner.query)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.search)
                            .onSubmit { planner.search() }
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

                if let error = planner.error {
                    Section { Text(error).foregroundColor(.secondary) }
                }

                if let route = planner.route, let destination = planner.destination {
                    Section {
                        RouteMapView(route: route)
                            .frame(height: 260)
                            .listRowInsets(EdgeInsets())
                    }

                    Section {
                        ValueRow(title: "Ziel", value: destination.name ?? "")
                        ValueRow(title: "Strecke", value: Format.kilometers(route.distance / 1000))
                        ValueRow(title: "Fahrzeit (ca. 18 km/h)",
                                 value: Format.duration(route.distance / 1000 / 18 * 3600))
                        if !planner.isCyclingRoute {
                            Text("Fußgängerroute als Näherung — Fahrradrouten liefert iOS einer App erst ab iOS 26. Apple Maps navigiert mit Fahrradrouten.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text(planner.isCyclingRoute ? "Fahrradroute" : "Route")
                    }

                    Section {
                        RangeCheck(distanceKm: route.distance / 1000,
                                   rangeKm: model.remainingRangeKm,
                                   weather: model.weather)
                    } header: {
                        Text("Reichweite")
                    }

                    Section {
                        Button {
                            planner.openInMaps(destination)
                        } label: {
                            Label("In Apple Maps navigieren", systemImage: "bicycle")
                        }
                    } footer: {
                        Text("Handy beim Fahren nur in einer festen Halterung nutzen und nicht bedienen.")
                    }
                }
            }
            .navigationTitle("Route")
            .onAppear {
                if let query = demoQuery, planner.route == nil {
                    planner.query = query
                    planner.search(selectFirst: true)
                }
            }
        }
    }
}

/// Vergleicht die Strecke mit der Restreichweite des Scooters.
private struct RangeCheck: View {
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

final class RoutePlanner: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [MKMapItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var destination: MKMapItem?
    @Published private(set) var route: MKRoute?
    @Published private(set) var isCyclingRoute = false
    @Published private(set) var error: String?

    private var activeSearch: MKLocalSearch?

    func search(selectFirst: Bool = false) {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        activeSearch?.cancel()
        isSearching = true
        error = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        let search = MKLocalSearch(request: request)
        activeSearch = search
        search.start { [weak self] response, error in
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

    func select(_ item: MKMapItem) {
        destination = item
        results = []
        route = nil
        error = nil
        if #available(iOS 26.0, *) {
            calculate(to: item, transport: .cycling)
        } else {
            calculate(to: item, transport: .walking)
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

    private func isCycling(_ transport: MKDirectionsTransportType) -> Bool {
        if #available(iOS 26.0, *) {
            return transport == .cycling
        }
        return false
    }

    private func calculate(to item: MKMapItem, transport: MKDirectionsTransportType) {
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = item
        request.transportType = transport
        MKDirections(request: request).calculate { [weak self] response, error in
            guard let self = self else { return }
            if let route = response?.routes.first {
                self.route = route
                self.isCyclingRoute = self.isCycling(transport)
            } else if self.isCycling(transport) {
                self.calculate(to: item, transport: .walking)
            } else {
                self.error = "Keine Route gefunden. Ist der Standort erlaubt?"
            }
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
