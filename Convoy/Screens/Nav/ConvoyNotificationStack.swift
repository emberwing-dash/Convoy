// ConvoyNotificationStack.swift
// Native iOS-style grouped notification banner stack with 3-second slide-out,
// card overlapping/deck stacking, and cross-session unread persistence.
import SwiftUI

// MARK: - Notification Item

struct ConvoyInAppNotification: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let message: String
    let symbol: String
    let symbolColorHex: UInt32
    let createdAt: Date
    var isRead: Bool

    var color: Color { Color(hex: symbolColorHex) }

    init(id: UUID = UUID(),
         title: String,
         message: String,
         symbol: String = "bell.fill",
         symbolColorHex: UInt32 = 0xE0281C,
         createdAt: Date = Date(),
         isRead: Bool = false) {
        self.id = id
        self.title = title
        self.message = message
        self.symbol = symbol
        self.symbolColorHex = symbolColorHex
        self.createdAt = createdAt
        self.isRead = isRead
    }
}

// MARK: - Notification Manager (State & Persistence)

@MainActor @Observable
final class ConvoyNotificationManager {
    static let shared = ConvoyNotificationManager()

    /// Active banners currently visible in the floating top-middle stack.
    var activeStack: [ConvoyInAppNotification] = []

    /// Persistent unread notifications preserved across app restarts and locks.
    var unreadHistory: [ConvoyInAppNotification] = []

    private let storageKey = "convoy_persistent_unread_notifications"
    private var dismissTimers: [UUID: Task<Void, Never>] = [:]

    init() {
        loadPersistentNotifications()
    }

    // MARK: - Post New Notification

    func post(title: String,
              message: String,
              symbol: String = "bell.fill",
              colorHex: UInt32 = 0xE0281C) {
        let notif = ConvoyInAppNotification(
            title: title,
            message: message,
            symbol: symbol,
            symbolColorHex: colorHex
        )

        // 1. Add to persistent store
        unreadHistory.insert(notif, at: 0)
        savePersistentNotifications()

        // 2. Add to active floating stack (top card)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            // Keep at most 3 overlapping in the visual deck
            activeStack.insert(notif, at: 0)
            if activeStack.count > 3 {
                activeStack.removeLast()
            }
        }

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // 3. Auto-dismiss / slide-out after exactly 3 seconds
        scheduleDismiss(id: notif.id)
    }

    // MARK: - Dismiss

    func dismiss(id: UUID) {
        dismissTimers[id]?.cancel()
        dismissTimers.removeValue(forKey: id)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            activeStack.removeAll { $0.id == id }
        }
    }

    func markAsRead(id: UUID) {
        if let idx = unreadHistory.firstIndex(where: { $0.id == id }) {
            unreadHistory[idx].isRead = true
            savePersistentNotifications()
        }
        dismiss(id: id)
    }

    func clearAllRead() {
        unreadHistory.removeAll { $0.isRead }
        savePersistentNotifications()
    }

    // MARK: - Persistence (preserved across app open/close)

    private func savePersistentNotifications() {
        if let data = try? JSONEncoder().encode(unreadHistory) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadPersistentNotifications() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([ConvoyInAppNotification].self, from: data)
        else { return }
        self.unreadHistory = list
    }

    private func scheduleDismiss(id: UUID) {
        dismissTimers[id]?.cancel()
        dismissTimers[id] = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.dismiss(id: id)
            }
        }
    }
}

// MARK: - iOS Native Style Notification Banner View

struct IPhoneNotificationBannerView: View {
    let notification: ConvoyInAppNotification
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            // App / category glyph
            ZStack {
                Circle()
                    .fill(notification.color.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: notification.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(notification.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Header line: App name + time
                HStack {
                    Text("CONVOY")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(CV.cream.opacity(0.55))
                        .tracking(0.8)
                    Spacer()
                    Text("now")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(CV.cream.opacity(0.45))
                }

                // Content
                Text(notification.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(notification.message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(CV.cream.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 356)
        .background(
            Color(hex: 0x18181C).opacity(0.92),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 14, y: 4)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { v in
                    // Swipe up to dismiss
                    if v.translation.height < -15 {
                        onDismiss()
                    }
                }
        )
    }
}

// MARK: - Overlapping Notification Stack Container (Top Middle)

struct ConvoyNotificationStackContainer: View {
    @Bindable var manager = ConvoyNotificationManager.shared

    var body: some View {
        if !manager.activeStack.isEmpty {
            ZStack(alignment: .top) {
                // Grouped card deck overlapping effect
                ForEach(Array(manager.activeStack.prefix(3).enumerated()), id: \.element.id) { index, notif in
                    let yOffset = CGFloat(index * 9)
                    let scale = 1.0 - CGFloat(index) * 0.045
                    let opacity = 1.0 - Double(index) * 0.22

                    IPhoneNotificationBannerView(notification: notif) {
                        manager.dismiss(id: notif.id)
                    }
                    .offset(y: yOffset)
                    .scaleEffect(scale, anchor: .top)
                    .opacity(opacity)
                    .zIndex(Double(50 - index))
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                }
            }
            .frame(width: 356)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 56) // Positioned top middle, just below the Dynamic Island/notch
        }
    }
}

// MARK: - Unread Notification History Drawer Sheet

struct UnreadNotificationsHistorySheet: View {
    @Bindable var manager = ConvoyNotificationManager.shared
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(CV.red)
                    Text("UNREAD NOTIFICATIONS")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CV.cream.opacity(0.6))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)

            if manager.unreadHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(CV.cream.opacity(0.4))
                        .padding(.top, 30)
                    Text("No unread alerts")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CV.cream.opacity(0.7))
                    Text("Warnings and proposals from convoy rides will appear here.")
                        .font(.system(size: 12))
                        .foregroundStyle(CV.cream.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(manager.unreadHistory) { item in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(item.color.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Image(systemName: item.symbol)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(item.color)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(item.title)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text(item.createdAt.formatted(.dateTime.hour().minute()))
                                            .font(.system(size: 11))
                                            .foregroundStyle(CV.cream.opacity(0.45))
                                    }
                                    Text(item.message)
                                        .font(.system(size: 12))
                                        .foregroundStyle(CV.cream.opacity(0.75))
                                }
                            }
                            .padding(12)
                            .background(
                                Color(hex: 0x1A1A1E),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color(hex: 0x121215))
    }
}

