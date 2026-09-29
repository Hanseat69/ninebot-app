//
//  TripViews.swift
//  Tab „Fahrten“: Fahrtenbuch-Liste, Details mit Karte und GPX-Export.
//

import SwiftUI
import MapKit

struct TripListView: View {
    @EnvironmentObject private var model: ScooterModel
    @EnvironmentObject private var store: TripStore

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

    var body: some View {
        if let trip = store.trips.first(where: { $0.id == tripID }) {
            List {
                if trip.points.count >= 2 {
                    Section {
                        TripMapView(points: trip.points)
                            .frame(height: 280)
                            .listRowInsets(EdgeInsets())
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

                Section {
                    if let url = gpxURL {
                        ShareLink(item: url) {
                            Label("Strecke als GPX exportieren", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Fahrt löschen", role: .destructive) {
                        store.delete(id: trip.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle(trip.start.formatted(date: .abbreviated, time: .omitted))
            .onAppear { gpxURL = store.gpxFile(for: trip) }
        } else {
            Text("Fahrt nicht gefunden").foregroundColor(.secondary)
        }
    }
}

/// Karte mit der gefahrenen Strecke (MapKit, damit es ab iOS 16 läuft).
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
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)
        let coordinates = points.map(\.coordinate)
        guard coordinates.count >= 2 else { return }

        let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
        map.addOverlay(line)

        let start = MKPointAnnotation()
        start.coordinate = coordinates[0]
        start.title = "Start"
        let end = MKPointAnnotation()
        end.coordinate = coordinates[coordinates.count - 1]
        end.title = "Ziel"
        map.addAnnotations([start, end])

        map.setVisibleMapRect(line.boundingMapRect,
                              edgePadding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30),
                              animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 4
            return renderer
        }
    }
}
