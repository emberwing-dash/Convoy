//
//  ConvoyWatchApp.swift
//  ConvoyWatch Watch App
//
//  Created by Rishav Goswami on 15/10/26.
//

import SwiftUI

@main
struct ConvoyWatch_Watch_AppApp: App {
    @StateObject private var locationManager = WatchLocationManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    WatchConnectivityManager.shared.activateSession()
                    locationManager.startLiveLocationUpdates()
                }
        }
    }
}
