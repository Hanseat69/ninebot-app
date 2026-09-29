//
//  ScooterActivityAttributes.swift
//  Daten der Live Activity (Sperrbildschirm / Dynamic Island).
//  Wird von App und Widget-Erweiterung gemeinsam benutzt.
//

import Foundation
import ActivityKit

@available(iOS 16.1, *)
struct ScooterActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var speed: Double?          // km/h laut GPS
        var battery: Int?           // %
        var distanceKm: Double
        var rangeKm: Double?        // Restreichweite laut Scooter
    }

    var scooterName: String
    var start: Date
}
