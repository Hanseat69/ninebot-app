//
//  DemoMode.swift
//  Tab-Leiste der App und — nur in Debug-Builds — ein Demo-Modus für
//  Screenshots: Start mit `-demoScreen <name>` zeigt einen bestimmten
//  Bildschirm mit Beispieldaten. In der Release-App ist der Demo-Modus aus.
//

import SwiftUI

enum DemoMode {
    #if DEBUG
    static let screen: String? = UserDefaults.standard.string(forKey: "demoScreen")
    #else
    static let screen: String? = nil
    #endif

    static var isActive: Bool { screen != nil }
}

enum AppTab: Hashable {
    case scooter, route, trips, battery, help
}

struct MainTabView: View {
    @State var selection: AppTab = .scooter
    var scooterScroll: String? = nil
    var routeDemoQuery: String? = nil
    var routeDemoNavigate = false
    /// Nur für Screenshots: ersetzt den Inhalt eines Tabs durch eine Unterseite.
    var overrideTab: AppTab? = nil
    var override: AnyView? = nil

    var body: some View {
        TabView(selection: $selection) {
            content(.scooter, ScooterView(scrollTarget: scooterScroll))
                .tabItem { Label("Scooter", systemImage: "scooter") }
                .tag(AppTab.scooter)
            content(.route, RoutePlannerView(demoQuery: routeDemoQuery, demoStartNavigation: routeDemoNavigate))
                .tabItem { Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond") }
                .tag(AppTab.route)
            content(.trips, TripListView())
                .tabItem { Label("Fahrten", systemImage: "map") }
                .tag(AppTab.trips)
            content(.battery, BatteryView())
                .tabItem { Label("Akku", systemImage: "battery.75") }
                .tag(AppTab.battery)
            content(.help, HelpView())
                .tabItem { Label("Hilfe", systemImage: "questionmark.circle") }
                .tag(AppTab.help)
        }
    }

    @ViewBuilder
    private func content<V: View>(_ tab: AppTab, _ view: V) -> some View {
        if tab == overrideTab, let override = override {
            override
        } else {
            view
        }
    }
}

#if DEBUG
import CoreLocation

/// Bildschirme für die Screenshot-Reihe.
struct DemoRootView: View {
    let screen: String
    @EnvironmentObject private var store: TripStore
    @EnvironmentObject private var documents: DocumentStore

    var body: some View {
        switch screen {
        case "scooter-settings":
            MainTabView(selection: .scooter, scooterScroll: "settings")
        case "scooter-vehicle":
            MainTabView(selection: .scooter, scooterScroll: "vehicle")
        case "scooter-more":
            MainTabView(selection: .scooter, scooterScroll: "weather")
        case "scooter-automation":
            MainTabView(selection: .scooter, scooterScroll: "automation")
        case "route-home":
            MainTabView(selection: .route)
        case "route":
            MainTabView(selection: .route, routeDemoQuery: "Elbphilharmonie Hamburg")
        case "navigation":
            MainTabView(selection: .route, routeDemoQuery: "Elbphilharmonie Hamburg", routeDemoNavigate: true)
        case "trips":
            MainTabView(selection: .trips)
        case "trip-detail":
            MainTabView(selection: .trips, overrideTab: .trips, override: AnyView(
                NavigationStack { TripDetailView(tripID: store.trips.first?.id ?? UUID()) }))
        case "battery":
            MainTabView(selection: .battery)
        case "help":
            MainTabView(selection: .help)
        case "help-specs":
            MainTabView(selection: .help, overrideTab: .help, override: AnyView(NavigationStack { SpecsHelp() }))
        case "help-errors":
            MainTabView(selection: .help, overrideTab: .help, override: AnyView(NavigationStack { ErrorCodesHelp() }))
        case "help-pdf":
            MainTabView(selection: .help, overrideTab: .help, override: AnyView(NavigationStack { ManualPDFView() }))
        case "maintenance":
            MainTabView(selection: .scooter, overrideTab: .scooter, override: AnyView(NavigationStack { MaintenanceView() }))
        case "documents":
            MainTabView(selection: .scooter, overrideTab: .scooter, override: AnyView(NavigationStack { DocumentsView() }))
        case "document-detail":
            MainTabView(selection: .scooter, overrideTab: .scooter, override: AnyView(NavigationStack {
                DocumentDetailView(documentID: documents.currentInsurance?.id ?? UUID())
            }))
        case "document-editor":
            DocumentEditor(kind: .insurance, existing: nil)
        default:
            MainTabView(selection: .scooter)
        }
    }
}

enum DemoData {
    static func load(screen: String, model: ScooterModel, documents: DocumentStore) {
        let connected = !["scooter-idle", "scooter-pairing"].contains(screen)
        model.loadDemo(connected: connected, pairing: screen == "scooter-pairing")
        model.store.loadDemo()
        documents.loadDemo()
    }
}
#endif
