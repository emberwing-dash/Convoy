//
//  WatchPairingSheet.swift
//  Convoy
//
//  Shows Apple Watch pairing status, live telemetry, and live map location.
//

import SwiftUI
import MapKit
import CoreLocation

struct WatchPairingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var watchManager = PhoneWatchConnectivityManager.shared
    
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isPingingWatch: Bool = false
    
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x360808), Color(hex: 0x1A0507), CV.bg],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Garage-style header with back button
                ZStack {
                    Text("Apple Watch").cvText(17, .semibold, color: CV.cream, inter: true)
                    HStack {
                        CircleBackButton { dismiss() }
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Pairing Card
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(watchManager.isReachable ? Color(hex: 0x1C2E24) : Color(hex: 0x2E1C1F))
                                    .frame(width: 64, height: 64)
                                Image(systemName: "applewatch")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(watchManager.isReachable ? CV.green : (watchManager.isWatchPaired ? Color(hex: 0xFFB020) : CV.red))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("Convoy Watch")
                                        .cvText(17, .bold, color: CV.cream, inter: true)
                                    Circle()
                                        .fill(watchManager.isReachable ? CV.green : (watchManager.isWatchPaired ? Color(hex: 0xFFB020) : Color.gray))
                                        .frame(width: 8, height: 8)
                                }
                                
                                Text(watchStatusSubtitle)
                                    .cvText(13, color: CV.cream.opacity(0.6), inter: true)
                            }
                            
                            Spacer()
                            
                            Button {
                                pingWatch()
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(isPingingWatch ? CV.cream.opacity(0.3) : Color(hex: 0xFFB020))
                                    .rotationEffect(.degrees(isPingingWatch ? 360 : 0))
                                    .animation(isPingingWatch ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isPingingWatch)
                                    .frame(width: 40, height: 40)
                                    .background(Color.white.opacity(0.06), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(18)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        
                        // Live Location Map Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(Color(hex: 0x007AFF))
                                Text("WATCH LIVE LOCATION")
                                    .cvText(11, .bold, color: CV.cream.opacity(0.5), tracking: 0.8, inter: true)
                                Spacer()
                                if let telemetry = watchManager.lastWatchLocation {
                                    Text(telemetry.timestamp.formatted(date: .omitted, time: .standard))
                                        .cvText(11, color: CV.cream.opacity(0.5), inter: true)
                                }
                            }
                            
                            if let telemetry = watchManager.lastWatchLocation {
                                Map(position: $mapPosition) {
                                    Annotation("Convoy Watch", coordinate: telemetry.coordinate) {
                                        ZStack {
                                            Circle()
                                                .fill(Color(hex: 0x007AFF).opacity(0.25))
                                                .frame(width: 50, height: 50)
                                            Circle()
                                                .fill(Color(hex: 0x007AFF))
                                                .frame(width: 26, height: 26)
                                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                            Image(systemName: "applewatch")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                                
                                // Telemetry details
                                HStack(spacing: 12) {
                                    metricPill("LAT / LON", String(format: "%.4f, %.4f", telemetry.coordinate.latitude, telemetry.coordinate.longitude))
                                    metricPill("SPEED", "\(Int(telemetry.speedKmh)) km/h")
                                    metricPill("ACCURACY", "±\(Int(telemetry.horizontalAccuracy))m")
                                }
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "applewatch.radiowaves.left.and.right")
                                        .font(.system(size: 36))
                                        .foregroundStyle(CV.muted)
                                        .padding(.top, 16)
                                    Text("Waiting for Watch Location")
                                        .cvText(15, .semibold, color: CV.cream, inter: true)
                                    Text("Open ConvoyWatch on your Apple Watch to stream your live GPS location.")
                                        .cvText(13, color: CV.muted, inter: true)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 20)
                                        .padding(.bottom, 16)
                                }
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                        .padding(18)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        
                        // Recent Watch Activity
                        VStack(alignment: .leading, spacing: 10) {
                            Text("WATCH TELEMETRY LOG")
                                .cvText(11, .bold, color: CV.cream.opacity(0.5), tracking: 0.8, inter: true)
                            
                            HStack {
                                Image(systemName: "bolt.horizontal.fill")
                                    .foregroundStyle(Color(hex: 0xFFB020))
                                Text(watchManager.lastReceivedAction.isEmpty ? "Connected & listening" : watchManager.lastReceivedAction)
                                    .cvText(13, .semibold, color: CV.cream, inter: true)
                                Spacer()
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .padding(18)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            watchManager.activateSession()
            if let loc = watchManager.lastWatchLocation {
                mapPosition = .region(MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
            }
        }
        .onChange(of: watchManager.lastWatchLocation) { _, newLoc in
            if let loc = newLoc {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    mapPosition = .region(MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                }
            }
        }
    }
    
    private var watchStatusSubtitle: String {
        if watchManager.isReachable {
            return "Connected & streaming live"
        } else if watchManager.isWatchAppInstalled {
            return "Paired · Open Watch app"
        } else if watchManager.isWatchPaired {
            return "Apple Watch Paired"
        } else {
            return "Searching for paired watch"
        }
    }
    
    private func pingWatch() {
        isPingingWatch = true
        watchManager.sendRideSync(rideTitle: "Convoy Ride", packFormation: "Standard", ridersCount: 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isPingingWatch = false
        }
    }
    
    private func metricPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).cvText(9, .bold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
            Text(value).cvText(12, .bold, color: CV.cream, inter: true).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
