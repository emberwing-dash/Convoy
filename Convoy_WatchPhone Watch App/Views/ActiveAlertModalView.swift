//
//  ActiveAlertModalView.swift
//  ConvoyWatch Watch App
//
//  Full-screen tactile alert presentation when an urgent notification occurs
//  (e.g., rider falls behind or gets separated), matching the Figma design system.
//

import SwiftUI

public struct ActiveAlertModalView: View {
    let alert: RideAlert
    @ObservedObject var rideManager: RideManager = .shared
    
    public init(alert: RideAlert) {
        self.alert = alert
    }
    
    public var body: some View {
        WatchCanvas {
            VStack(spacing: 0) {
                // Header: Icon + "CONVOY" + "now"
                HStack(spacing: 7) {
                    if let avatar = alert.riderAvatar {
                        SenderAvatar(image: avatar, size: 22)
                    } else {
                        ZStack {
                            Circle()
                                .fill(alert.severity == .critical ? W.red : W.amber)
                                .frame(width: 22, height: 22)
                            Image(systemName: alert.kind.iconName)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    
                    Text("CONVOY")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.22)
                        .foregroundStyle(W.secondary)
                    
                    Spacer(minLength: 0)
                    
                    Text("now")
                        .font(.system(size: 11))
                        .tracking(-0.165)
                        .foregroundStyle(W.secondary)
                }
                
                // Alert Title & Details
                VStack(alignment: .leading, spacing: 3) {
                    Text(alert.title)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.24)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !alert.detail.isEmpty {
                        Text(alert.detail)
                            .font(.system(size: 13))
                            .tracking(-0.21)
                            .foregroundStyle(W.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 8)
                
                Spacer(minLength: 8)
                
                // Glanceable Action Buttons
                VStack(spacing: 6) {
                    if !alert.actions.isEmpty {
                        ForEach(Array(alert.actions.enumerated()), id: \.offset) { index, actionText in
                            ActionButton(
                                title: actionText,
                                style: index == 0 ? (alert.severity == .critical ? .red : .amber) : .dark,
                                height: 34
                            ) {
                                rideManager.respondToAlert(action: actionText)
                            }
                        }
                    } else {
                        ActionButton(
                            title: "Dismiss",
                            style: .dark,
                            height: 36
                        ) {
                            rideManager.dismissActiveAlert()
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 26)
            .padding(.bottom, 12)
        }
    }
}
