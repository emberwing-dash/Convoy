// NotificationView.swift
import SwiftUI

struct NotificationView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Notifications")
                        .cvText(34, .bold, color: Color(hex: 0xF5EDDE),
                                tracking: -0.68, inter: true)
                        .padding(.top, 62)
                        .padding(.bottom, 24)

                    if app.notifications.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 10) {
                            ForEach(app.notifications) { notif in
                                notificationRow(notif)
                            }
                        }
                        .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)

            CircleBackButton { app.pop() }
                .padding(.leading, 20)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await app.refreshNotifications(force: true)
        }
        .task {
            // Always refresh on entry — this screen exists specifically to
            // surface new arrivals from other users.
            await app.refreshNotifications(force: true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 30))
                .foregroundStyle(CV.cream.opacity(0.5))
            Text("No new notifications")
                .cvText(17, .semibold, inter: true)
            Text("Friend requests, crew invites and ride joins from the last two days will appear here.")
                .cvText(14, color: CV.muted, inter: true)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.top, 20)
    }

    private func notificationRow(_ notif: AppNotification) -> some View {
        HStack(spacing: 12) {
            AvatarChip(data: notif.avatarData, name: notif.title, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(notif.title)
                    .cvText(15, .bold, inter: true)
                Text(notif.subtitle)
                    .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                    .lineLimit(2)
            }

            Spacer()

            if notif.status == .pending {
                HStack(spacing: 8) {
                    Button {
                        Task { await app.acceptNotification(notif) }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CV.ink)
                            .frame(width: 36, height: 36)
                            .background(CV.cream, in: Circle())
                    }.buttonStyle(.plain)

                    Button {
                        Task { await app.declineNotification(notif) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CV.cream)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }.buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: notif.status == .accepted
                          ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12))
                    Text(notif.status == .accepted ? "Accepted" : "Declined")
                        .cvText(12, .semibold, inter: true)
                }
                .foregroundStyle(notif.status == .accepted ? CV.green : CV.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    (notif.status == .accepted ? CV.green : CV.muted).opacity(0.12),
                    in: Capsule()
                )
            }
        }
        .padding(14)
        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}
