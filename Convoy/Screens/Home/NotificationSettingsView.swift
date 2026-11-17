// NotificationSettingsView.swift
// Push preferences per category. Saved to `notification_prefs`; the server checks them before
// queueing a push. SOS alerts from your convoy are always delivered.
import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var prefs: NotificationPrefs?
    @State private var systemStatus: UNAuthorizationStatus = .notDetermined
    @State private var saveFailed = false

    var body: some View {
        ZStack(alignment: .top) {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Notifications")
                        .cvText(32, .bold, color: CV.text, tracking: -0.6, inter: true)
                        .padding(.top, 64)
                    Text("Choose what Convoy tells you about when you're not in the app.")
                        .cvText(15, color: CV.muted, lineHeight: 21, inter: true)
                        .padding(.top, 6)

                    if systemStatus == .denied {
                        systemOffCard.padding(.top, 20)
                    }

                    if let binding = Binding($prefs) {
                        section("PUSH") {
                            row("Allow push notifications", "bell.badge.fill", binding.push_enabled)
                        }
                        section("WHAT TO SEND") {
                            row("Rides", "flag.2.crossed.fill", binding.rides,
                                note: "Invites, changes to time or route, start, cancel, reminders")
                            divider
                            row("Crews", "person.3.fill", binding.crews, note: "Crew invites and members joining or leaving")
                            divider
                            row("Friends", "person.2.fill", binding.friends, note: "Friend requests and accepted requests")
                            divider
                            row("Community", "bubble.left.and.bubble.right.fill", binding.community, note: "Likes, comments and new posts")
                            divider
                            row("Navigation alerts", "location.north.line.fill", binding.navigation,
                                note: "“Slow down” / “Catch up” when you drift from the group")
                            divider
                            row("Achievements", "trophy.fill", binding.achievements, note: "Milestones and monthly leaderboard")
                        }
                        .opacity(binding.push_enabled.wrappedValue ? 1 : 0.45)
                        .disabled(!binding.push_enabled.wrappedValue)

                        HStack(spacing: 8) {
                            Image(systemName: "sos").font(.system(size: 12, weight: .black))
                                .foregroundStyle(CV.danger)
                            Text("SOS alerts from riders in your convoy are always delivered.")
                                .cvText(12, color: CV.muted, inter: true)
                        }
                        .padding(.top, 14).padding(.leading, 4)

                        if saveFailed {
                            Text("Couldn't save. Check your connection.")
                                .cvText(12, color: CV.danger, inter: true)
                                .padding(.top, 10).padding(.leading, 4)
                        }
                    } else {
                        ProgressView().tint(CV.text).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)

            CircleBackButton { app.pop() }
                .padding(.leading, 20).padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .task {
            await refreshSystemStatus()
            guard let id = await app.resolvedUserId() else { return }
            await NotificationPrefsStore.shared.load(userId: id)
            prefs = NotificationPrefsStore.shared.prefs
        }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await refreshSystemStatus() } } }
        .onChange(of: prefs) { old, new in
            guard old != nil, let new else { return }
            Task { saveFailed = !(await NotificationPrefsStore.shared.save(new)) }
        }
    }

    private func refreshSystemStatus() async {
        systemStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if systemStatus == .notDetermined { await PushNotificationManager.shared.requestAuthorizationAndRegister() }
    }

    private var systemOffCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Notifications are off for Convoy", systemImage: "bell.slash.fill")
                .cvText(15, .semibold, color: CV.text, inter: true)
                .foregroundStyle(CV.warning)
            Text("Turn them on in iOS Settings to get ride updates and SOS alerts when the app is closed.")
                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            } label: { Text("Open Settings") }
            .buttonStyle(CVPrimaryButtonStyle(height: 44))
        }
        .padding(16)
        .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(CV.warning.opacity(0.35), lineWidth: 1))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).cvText(12, .semibold, color: CV.muted, tracking: 0.6, inter: true).padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(CV.stroke, lineWidth: 1))
        }
        .padding(.top, 24)
    }

    private var divider: some View { Rectangle().fill(CV.separator).frame(height: 0.5).padding(.leading, 64) }

    private func row(_ title: String, _ icon: String, _ value: Binding<Bool>, note: String? = nil) -> some View {
        Toggle(isOn: value) {
            HStack(spacing: 14) {
                IconBadge(symbol: icon, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).cvText(15, .semibold, color: CV.text, inter: true)
                    if let note { Text(note).cvText(12, color: CV.muted, lineHeight: 16, inter: true) }
                }
            }
        }
        .tint(CV.success)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
