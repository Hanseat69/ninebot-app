//
//  Navigation.swift
//  Navigation direkt in der App: Abbiegehinweise mit großen Pfeilen,
//  deutsche Sprachansagen, Neuberechnung beim Abweichen, Ankunft mit Rückweg.
//  Dazu Favoriten und der Reichweitenkreis für den Tab „Route“.
//

import Foundation
import SwiftUI
import MapKit
import CoreLocation
import AVFoundation

// MARK: - Navigation

final class NavigationController: NSObject, ObservableObject, Identifiable, CLLocationManagerDelegate {

    let id = UUID()
    let destination: MKMapItem
    /// Startpunkt, für den Rückweg.
    let origin: CLLocationCoordinate2D?

    @Published private(set) var route: MKRoute
    @Published private(set) var stepIndex = 0
    @Published private(set) var distanceToManeuver: CLLocationDistance = 0
    @Published private(set) var remainingDistance: CLLocationDistance
    @Published private(set) var location: CLLocation?
    @Published private(set) var arrived = false
    @Published private(set) var isRerouting = false
    @Published var voiceEnabled = true {
        didSet { if !voiceEnabled { speech.stopSpeaking(at: .immediate) } }
    }

    private let manager = CLLocationManager()
    private let speech = AVSpeechSynthesizer()
    private var announced: Set<String> = []
    private var offRouteCount = 0

    init(route: MKRoute, destination: MKMapItem, origin: CLLocationCoordinate2D?) {
        self.route = route
        self.destination = destination
        self.origin = origin
        self.remainingDistance = route.distance
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .otherNavigation
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Schritte mit Anweisung (der erste Schritt von MapKit ist oft leer).
    private var steps: [MKRoute.Step] { route.steps }

    var nextInstruction: String? {
        guard stepIndex + 1 < steps.count else { return arrived ? nil : "Ziel erreichen" }
        return steps[stepIndex + 1].instructions.isEmpty ? nil : steps[stepIndex + 1].instructions
    }

    var followingInstruction: String? {
        guard stepIndex + 2 < steps.count else { return nil }
        let text = steps[stepIndex + 2].instructions
        return text.isEmpty ? nil : text
    }

    var estimatedArrival: Date {
        // Scooter-typische 18 km/h = 5 m/s
        Date().addingTimeInterval(remainingDistance / 5)
    }

    func start() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt,
                                                         options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        if let first = steps.first(where: { !$0.instructions.isEmpty })?.instructions {
            say("Navigation gestartet. \(first)")
        } else {
            say("Navigation gestartet.")
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.allowsBackgroundLocationUpdates = false
        speech.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Standort

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 50 else { return }
        location = loc
        update(with: loc)
    }

    private func update(with loc: CLLocation) {
        guard !arrived, !steps.isEmpty else { return }
        let point = MKMapPoint(loc.coordinate)

        // Ankunft
        if loc.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude,
                                         longitude: destination.placemark.coordinate.longitude)) < 25 {
            arrive()
            return
        }

        // Abweichung von der Route → neu berechnen
        let offRoute = NavigationController.distance(from: point, to: route.polyline)
        if offRoute > 40 && loc.horizontalAccuracy < 30 {
            offRouteCount += 1
            if offRouteCount >= 3 { reroute(from: loc) }
        } else {
            offRouteCount = 0
        }

        // Aktuellen Schritt bestimmen: den nächstgelegenen der kommenden drei
        var best = stepIndex
        var bestDistance = Double.greatestFiniteMagnitude
        for i in stepIndex..<min(stepIndex + 3, steps.count) where steps[i].polyline.pointCount > 0 {
            let d = NavigationController.distance(from: point, to: steps[i].polyline)
            if d < bestDistance - 5 { best = i; bestDistance = d }
        }
        stepIndex = best

        // Entfernung bis zum Ende des aktuellen Schritts = nächstes Manöver
        let polyline = steps[stepIndex].polyline
        if polyline.pointCount > 0 {
            let end = polyline.points()[polyline.pointCount - 1]
            distanceToManeuver = point.distance(to: end)
            if distanceToManeuver < 12 && stepIndex + 1 < steps.count {
                stepIndex += 1
            }
        }
        remainingDistance = distanceToManeuver + steps.dropFirst(stepIndex + 1).reduce(0) { $0 + $1.distance }
        announce()
    }

    private func announce() {
        guard let next = nextInstruction else { return }
        let key = "\(stepIndex)"
        if distanceToManeuver <= 220 && distanceToManeuver > 60 && !announced.contains(key + "-far") {
            announced.insert(key + "-far")
            say("In \(Format.spokenDistance(distanceToManeuver)): \(next)")
        } else if distanceToManeuver <= 35 && !announced.contains(key + "-near") {
            announced.insert(key + "-near")
            say(next)
        }
    }

    private func arrive() {
        arrived = true
        distanceToManeuver = 0
        remainingDistance = 0
        say("Du hast dein Ziel erreicht.")
    }

    private func reroute(from loc: CLLocation) {
        guard !isRerouting else { return }
        isRerouting = true
        offRouteCount = 0
        say("Route wird neu berechnet.")
        RoutePlanner.calculateRoute(from: MKMapItem(placemark: MKPlacemark(coordinate: loc.coordinate)),
                                    to: destination) { [weak self] route, _ in
            guard let self = self else { return }
            self.isRerouting = false
            if let route = route {
                self.route = route
                self.stepIndex = 0
                self.announced = []
                self.remainingDistance = route.distance
            }
        }
    }

    private func say(_ text: String) {
        guard voiceEnabled, !DemoMode.isActive else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        speech.speak(utterance)
    }

    // MARK: Geometrie

    /// Kürzeste Entfernung (Meter) von einem Punkt zu einer Linie.
    static func distance(from p: MKMapPoint, to polyline: MKPolyline) -> Double {
        let points = polyline.points()
        let count = polyline.pointCount
        guard count > 0 else { return .greatestFiniteMagnitude }
        guard count > 1 else { return p.distance(to: points[0]) }
        var best = Double.greatestFiniteMagnitude
        for i in 0..<(count - 1) {
            let a = points[i], b = points[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let length2 = dx * dx + dy * dy
            var t = length2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2 : 0
            t = min(max(t, 0), 1)
            best = min(best, p.distance(to: MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)))
        }
        return best
    }

    /// Pfeilsymbol aus dem Anweisungstext (MapKit liefert keinen Manövertyp).
    static func symbol(for instruction: String?) -> String {
        guard let text = instruction?.lowercased() else { return "flag.checkered" }
        if text.contains("ziel") || text.contains("destination") || text.contains("arrive") { return "flag.checkered" }
        if text.contains("wenden") || text.contains("u-turn") { return "arrow.uturn.left" }
        if text.contains("kreisverkehr") || text.contains("roundabout") { return "arrow.triangle.turn.up.right.circle" }
        let left = text.contains("links") || text.contains("left")
        let right = text.contains("rechts") || text.contains("right")
        let slight = text.contains("leicht") || text.contains("halb") || text.contains("halten")
            || text.contains("slight") || text.contains("keep")
        if left { return slight ? "arrow.up.left" : "arrow.turn.up.left" }
        if right { return slight ? "arrow.up.right" : "arrow.turn.up.right" }
        return "arrow.up"
    }
}

extension Format {
    static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int((meters / 10).rounded()) * 10) m"
        }
        return String(format: "%.1f km", locale: Locale.current, meters / 1000)
    }

    static func spokenDistance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int((meters / 50).rounded()) * 50) Metern" : Format.distance(meters)
    }
}

// MARK: - Navigationsbildschirm

struct NavigationScreen: View {
    @ObservedObject var nav: NavigationController
    @EnvironmentObject private var model: ScooterModel
    let onReturnTrip: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            maneuverPanel
            NavigationMapView(route: nav.route, destination: nav.destination.placemark.coordinate)
                .overlay(alignment: .bottom) {
                    if nav.arrived { arrivalCard.padding() }
                }
            infoBar
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // Display bleibt an
            nav.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            nav.stop()
        }
    }

    private var maneuverPanel: some View {
        HStack(spacing: 16) {
            Image(systemName: nav.isRerouting ? "arrow.triangle.2.circlepath"
                                              : NavigationController.symbol(for: nav.nextInstruction))
                .font(.system(size: 54, weight: .bold))
                .frame(width: 72)
            VStack(alignment: .leading, spacing: 4) {
                if nav.isRerouting {
                    Text("Route wird neu berechnet …").font(.title3.bold())
                } else if nav.arrived {
                    Text("Ziel erreicht").font(.title2.bold())
                } else {
                    Text(Format.distance(nav.distanceToManeuver))
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                    Text(nav.nextInstruction ?? "")
                        .font(.headline)
                        .lineLimit(2)
                    if let then = nav.followingInstruction {
                        Text("Danach: \(then)")
                            .font(.caption)
                            .opacity(0.8)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                nav.voiceEnabled.toggle()
            } label: {
                Image(systemName: nav.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title3)
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.2)))
            }
        }
        .foregroundColor(.white)
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.02, green: 0.35, blue: 0.3).ignoresSafeArea(edges: .top))
    }

    private var infoBar: some View {
        HStack(alignment: .center) {
            infoItem(value: nav.location.map { $0.speed >= 0 ? String(format: "%.0f", $0.speed * 3.6) : "–" } ?? "–",
                     unit: "km/h")
            infoItem(value: model.batteryPercent.map { "\($0)" } ?? "–", unit: "% Akku", warn: rangeIsTight)
            infoItem(value: Format.distance(nav.remainingDistance), unit: "noch")
            infoItem(value: nav.estimatedArrival.formatted(date: .omitted, time: .shortened), unit: "Ankunft")
            Button(role: .destructive) {
                onClose()
            } label: {
                Text("Ende")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.red))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private func infoItem(value: String, unit: String, warn: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
                .foregroundColor(warn ? .orange : .primary)
            Text(unit).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Restreichweite laut Scooter reicht knapp nicht für die Reststrecke.
    private var rangeIsTight: Bool {
        guard let range = model.remainingRangeKm else { return false }
        return range * 0.9 < nav.remainingDistance / 1000
    }

    private var arrivalCard: some View {
        VStack(spacing: 12) {
            Label("Du hast dein Ziel erreicht", systemImage: "flag.checkered")
                .font(.headline)
            HStack {
                if let onReturnTrip = onReturnTrip, nav.origin != nil {
                    Button {
                        onReturnTrip()
                    } label: {
                        Label("Rückweg starten", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Beenden") { onClose() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial))
    }
}

/// Karte, die der Position folgt (in Fahrtrichtung gedreht).
private struct NavigationMapView: UIViewRepresentable {
    let route: MKRoute
    let destination: CLLocationCoordinate2D

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.setUserTrackingMode(.followWithHeading, animated: false)
        let pin = MKPointAnnotation()
        pin.coordinate = destination
        pin.title = "Ziel"
        map.addAnnotation(pin)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        guard context.coordinator.shownRoute !== route else { return }
        context.coordinator.shownRoute = route
        map.removeOverlays(map.overlays)
        map.addOverlay(route.polyline)
        if map.userLocation.location == nil {
            map.setVisibleMapRect(route.polyline.boundingMapRect,
                                  edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var shownRoute: MKRoute?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 7
            renderer.lineCap = .round
            return renderer
        }
    }
}

// MARK: - Reichweitenkreis

/// Zwei Kreise um den Standort: grün = hin und zurück, orange = nur hin.
/// Luftlinie, daher mit Umwegfaktor 1,3 für echte Straßen.
struct RangeMapView: UIViewRepresentable {
    let center: CLLocationCoordinate2D
    let usableRangeKm: Double

    static let detourFactor = 1.3

    var oneWayMeters: Double { usableRangeKm * 1000 / Self.detourFactor }
    var roundTripMeters: Double { oneWayMeters / 2 }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.isRotateEnabled = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        let oneWay = MKCircle(center: center, radius: oneWayMeters)
        oneWay.title = "oneWay"
        let roundTrip = MKCircle(center: center, radius: roundTripMeters)
        roundTrip.title = "roundTrip"
        map.addOverlays([oneWay, roundTrip])
        map.setVisibleMapRect(oneWay.boundingMapRect,
                              edgePadding: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKCircleRenderer(circle: circle)
            let color: UIColor = circle.title == "roundTrip" ? .systemGreen : .systemOrange
            renderer.fillColor = color.withAlphaComponent(0.12)
            renderer.strokeColor = color
            renderer.lineWidth = 2
            return renderer
        }
    }
}

// MARK: - Favoriten

struct FavoritePlace: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var symbol: String {
        switch name {
        case "Zuhause": return "house.fill"
        case "Arbeit": return "briefcase.fill"
        default: return "star.fill"
        }
    }

    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        return item
    }
}

final class FavoritePlaces: ObservableObject {
    @Published private(set) var places: [FavoritePlace] = []

    private static let key = "favoritePlaces"

    init() {
        if let data = UserDefaults.standard.data(forKey: FavoritePlaces.key),
           let saved = try? JSONDecoder().decode([FavoritePlace].self, from: data) {
            places = saved
        }
    }

    /// Speichert ein Ziel; „Zuhause“ und „Arbeit“ gibt es jeweils nur einmal.
    func save(name: String, item: MKMapItem) {
        let place = FavoritePlace(name: name,
                                  address: item.placemark.title ?? item.name ?? "",
                                  latitude: item.placemark.coordinate.latitude,
                                  longitude: item.placemark.coordinate.longitude)
        places.removeAll { $0.name == name }
        let order = ["Zuhause": 0, "Arbeit": 1]
        places.append(place)
        places.sort { (order[$0.name] ?? 2, $0.name) < (order[$1.name] ?? 2, $1.name) }
        persist()
    }

    func delete(_ place: FavoritePlace) {
        places.removeAll { $0.id == place.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: FavoritePlaces.key)
        }
    }

    #if DEBUG
    func loadDemo() {
        places = [
            FavoritePlace(name: "Zuhause", address: "Eppendorfer Weg 88, Hamburg", latitude: 53.5760, longitude: 9.9640),
            FavoritePlace(name: "Arbeit", address: "Großer Burstah 31, Hamburg", latitude: 53.5480, longitude: 9.9890),
            FavoritePlace(name: "Stadtpark", address: "Hamburg-Winterhude", latitude: 53.5960, longitude: 10.0200),
        ]
    }
    #endif
}
