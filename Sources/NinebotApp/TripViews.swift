//
//  TripViews.swift
//  Tab „Fahrten“: Fahrtenbuch-Liste, Details mit Karte und GPX-Export.
//

import SwiftUI
import MapKit

struct TripListView: View {
    @EnvironmentObject private var model: ScooterModel
    @EnvironmentObject private var store: TripStore
    @State private var allTripsCSV: URL?

    var body: some View {
        NavigationStack {
            List {
                if let trip = model.activeTrip {
                    Section("Aktuelle Fahrt") {
                        ValueRow(title: "Seit", value: trip.start.formatted(date: .omitted, time: .shortened))
                        ValueRow(title: "Dauer", value: Format.duration(trip.duration))
                        ValueRow(title: "Strecke", value: Format.kilometers(trip.distanceKm))
                        if let speed = model.gpsSpeed {
                            ValueRow(title: "Geschwindigkeit (GPS)", value: Format.speed(speed))
                        }
                    }
                }

                if store.trips.isEmpty {
                    Section {
                        Text("Noch keine Fahrten. Sobald dein Scooter verbunden ist, wird jede Fahrt automatisch aufgezeichnet.")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section("Gesamt") {
                        ValueRow(title: "Fahrten", value: "\(store.trips.count)")
                        ValueRow(title: "Strecke", value: Format.kilometers(store.trips.reduce(0) { $0 + $1.distanceKm }))
                        ValueRow(title: "Fahrzeit", value: Format.duration(store.trips.reduce(0) { $0 + $1.duration }))
                    }
                    Section("Fahrten") {
                        ForEach(store.trips) { trip in
                            NavigationLink {
                                TripDetailView(tripID: trip.id)
                            } label: {
                                TripRow(trip: trip)
                            }
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("Fahrtenbuch")
            .toolbar {
                if !store.trips.isEmpty, let url = allTripsCSV {
                    ShareLink(item: url) {
                        Label("Als CSV exportieren", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .onAppear { allTripsCSV = store.csvFileForAllTrips() }
            .onChange(of: store.trips.count) { _ in allTripsCSV = store.csvFileForAllTrips() }
        }
    }
}

struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.start.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            HStack(spacing: 12) {
                Label(Format.kilometers(trip.distanceKm), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Label(Format.duration(trip.duration), systemImage: "clock")
                if let used = trip.batteryUsed {
                    Label("\(used) %", systemImage: "battery.50")
                }
                if let weather = trip.weather {
                    Label(String(format: "%.0f°", weather.temperature), systemImage: weather.symbol)
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            if let from = trip.startAddress, let to = trip.endAddress {
                Text("\(from) → \(to)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct TripDetailView: View {
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var gpxURL: URL?
    @State private var csvURL: URL?

    var body: some View {
        if let trip = store.trips.first(where: { $0.id == tripID }) {
            List {
                if trip.points.count >= 2 {
                    Section {
                        TripMapView(points: trip.points)
                            .frame(height: 280)
                            .listRowInsets(EdgeInsets())
                        SpeedLegend()
                    }
                }

                Section("Zeit") {
                    ValueRow(title: "Datum", value: trip.start.formatted(date: .complete, time: .omitted))
                    ValueRow(title: "Abfahrt", value: trip.start.formatted(date: .omitted, time: .shortened))
                    ValueRow(title: "Ankunft", value: trip.end.formatted(date: .omitted, time: .shortened))
                    ValueRow(title: "Dauer", value: Format.duration(trip.duration))
                }

                Section("Strecke") {
                    ValueRow(title: "Strecke", value: Format.kilometers(trip.distanceKm))
                    if let km = trip.scooterDistance {
                        ValueRow(title: "laut Scooter", value: Format.kilometers(km))
                    }
                    ValueRow(title: "laut GPS", value: Format.kilometers(trip.gpsDistance / 1000))
                    if let avg = trip.averageSpeed {
                        ValueRow(title: "Ø Geschwindigkeit", value: Format.speed(avg))
                    }
                    if trip.maxSpeed > 0 {
                        ValueRow(title: "Höchstgeschwindigkeit (GPS)", value: Format.speed(trip.maxSpeed))
                    }
                    if let from = trip.startAddress {
                        ValueRow(title: "Start", value: from)
                    }
                    if let to = trip.endAddress {
                        ValueRow(title: "Ziel", value: to)
                    }
                }

                Section("Akku") {
                    if let s = trip.startBattery, let e = trip.endBattery {
                        ValueRow(title: "Akku", value: "\(s) % → \(e) %")
                    }
                    if let c = trip.consumptionPerKm {
                        ValueRow(title: "Verbrauch", value: String(format: "%.1f %% pro km", locale: Locale.current, c))
                    }
                    ValueRow(title: "Scooter", value: trip.scooterName)
                }

                if let weather = trip.weather {
                    Section("Wetter bei Abfahrt") {
                        Label(weather.summary, systemImage: weather.symbol)
                        ValueRow(title: "Temperatur", value: String(format: "%.0f °C", locale: Locale.current, weather.temperature))
                        ValueRow(title: "Wind", value: String(format: "%.0f km/h", locale: Locale.current, weather.windSpeed))
                    }
                }

                Section {
                    if let url = gpxURL {
                        ShareLink(item: url) {
                            Label("Strecke als GPX exportieren", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let url = csvURL {
                        ShareLink(item: url) {
                            Label("GPS-Punkte als CSV exportieren", systemImage: "tablecells")
                        }
                    }
                    Button("Fahrt löschen", role: .destructive) {
                        store.delete(id: trip.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(trip.start.formatted(date: .abbreviated, time: .omitted))
            .onAppear {
                gpxURL = store.gpxFile(for: trip)
                csvURL = store.csvFile(for: trip)
            }
        } else {
            Text("Fahrt nicht gefunden").foregroundColor(.secondary)
        }
    }
}

/// Farbstufen für das Tempo auf der Karte (km/h laut GPS).
enum SpeedBand: Int, CaseIterable {
    case slow, medium, fast, top

    init(kmh: Double) {
        switch kmh {
        case ..<8: self = .slow
        case ..<14: self = .medium
        case ..<18: self = .fast
        default: self = .top
        }
    }

    var label: String {
        switch self {
        case .slow: return "< 8"
        case .medium: return "8–14"
        case .fast: return "14–18"
        case .top: return "≥ 18 km/h"
        }
    }

    var color: UIColor {
        switch self {
        case .slow: return .systemBlue
        case .medium: return .systemGreen
        case .fast: return .systemOrange
        case .top: return .systemRed
        }
    }
}

struct SpeedLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(SpeedBand.allCases, id: \.self) { band in
                HStack(spacing: 4) {
                    Circle().fill(Color(band.color)).frame(width: 8, height: 8)
                    Text(band.label)
                }
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}

/// Teilstück der Strecke in einer Tempo-Farbstufe.
final class SpeedPolyline: MKPolyline {
    var band: SpeedBand = .slow
}

/// Karte mit der gefahrenen Strecke, nach Tempo eingefärbt (MapKit, ab iOS 16).
struct TripMapView: UIViewRepresentable {
    let points: [TripPoint]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        guard context.coordinator.shownCount != points.count else { return }
        context.coordinator.shownCount = points.count
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        guard points.count >= 2 else { return }

        // Aufeinanderfolgende Punkte gleicher Farbstufe zu einer Linie zusammenfassen.
        var segments: [SpeedPolyline] = []
        var current: [CLLocationCoordinate2D] = [points[0].coordinate]
        var band = SpeedBand(kmh: max(points[0].speed, 0) * 3.6)
        for point in points.dropFirst() {
            let pointBand = point.speed >= 0 ? SpeedBand(kmh: point.speed * 3.6) : band
            current.append(point.coordinate)
            if pointBand != band {
                segments.append(Self.polyline(current, band))
                current = [point.coordinate]
                band = pointBand
            }
        }
        if current.count >= 2 { segments.append(Self.polyline(current, band)) }
        map.addOverlays(segments)

        let start = MKPointAnnotation()
        start.coordinate = points[0].coordinate
        start.title = "Start"
        let end = MKPointAnnotation()
        end.coordinate = points[points.count - 1].coordinate
        end.title = "Ziel"
        map.addAnnotations([start, end])

        let all = points.map(\.coordinate)
        let bounds = MKPolyline(coordinates: all, count: all.count).boundingMapRect
        map.setVisibleMapRect(bounds, edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30),
                              animated: false)
    }

    private static func polyline(_ coordinates: [CLLocationCoordinate2D], _ band: SpeedBand) -> SpeedPolyline {
        let line = SpeedPolyline(coordinates: coordinates, count: coordinates.count)
        line.band = band
        return line
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var shownCount = -1

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = (line as? SpeedPolyline)?.band.color ?? .systemBlue
            renderer.lineWidth = 5
            renderer.lineCap = .round
            return renderer
        }
    }
}
