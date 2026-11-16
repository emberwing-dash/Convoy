// SocialComponents.swift — small building blocks shared by the Crew tab screens.
import SwiftUI

enum CVSocial {
    static let amber = CV.warning
    static let silver = Color(hex: 0xC7C9D1)
    static let bronze = Color(hex: 0xC98A5B)
    static let card = CV.surface
    static let headline = CV.text
}

/// Card used for every "nothing here yet" state, with an optional call to action.
struct EmptyStateCard: View {
    var icon: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(CV.text.opacity(0.7))
                .frame(width: 54, height: 54)
                .background(Color.white.opacity(0.06), in: Circle())
            Text(title)
                .cvText(17, .bold, color: CVSocial.headline, inter: true)
                .multilineTextAlignment(.center)
            Text(message)
                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .cvText(14, .bold, color: CV.onAccent, inter: true)
                        .padding(.horizontal, 20).frame(height: 42)
                        .background(CV.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 20)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// Inline error with retry, used when a request to the server fails.
struct RetryCard: View {
    var message: String
    var retry: () -> Void
    var body: some View {
        EmptyStateCard(icon: "wifi.exclamationmark", title: "Couldn't load", message: message,
                       actionTitle: "Try again", action: retry)
    }
}

struct SectionTitleRow: View {
    var title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).cvText(20, .bold, color: CVSocial.headline, inter: true)
                if let subtitle { Text(subtitle).cvText(13, color: CV.muted, inter: true) }
            }
            Spacer()
            if let trailing, let action {
                Button(action: action) { Text(trailing).cvText(15, .semibold, color: CV.accent, inter: true) }
                    .buttonStyle(.plain)
            }
        }
    }
}

/// The one relationship button: Add friend → Requested → Friends (or Accept when they asked you).
struct FriendButton: View {
    @Environment(AppState.self) private var app
    let riderId: UUID
    var compact = false
    @State private var error: String?

    var body: some View {
        let state = app.friendState(riderId)
        let busy = app.friendBusy.contains(riderId)
        let (title, icon, filled): (String, String, Bool) = {
            switch state {
            case .none: return ("Add friend", "person.badge.plus", true)
            case .incoming: return ("Accept", "checkmark", true)
            case .requested: return ("Requested", "clock", false)
            case .friends: return ("Friends", "person.2.fill", false)
            }
        }()
        Button {
            guard state == .none || { if case .incoming = state { return true } else { return false } }() else { return }
            Task {
                do { try await app.addFriend(riderId) }
                catch { self.error = (error as NSError).localizedDescription }
            }
        } label: {
            ZStack {
                if busy { ProgressView().tint(filled ? CV.onAccent : CV.text) }
                else {
                    HStack(spacing: 6) {
                        Image(systemName: icon).font(.system(size: compact ? 12 : 13, weight: .semibold))
                        Text(title).font(.system(size: compact ? 14 : 15, weight: .semibold))
                    }
                    .foregroundStyle(filled ? CV.onAccent : CV.text)
                }
            }
            .frame(maxWidth: .infinity).frame(height: compact ? 36 : 40)
            .background(filled ? Color.white : Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(filled ? 0 : 0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(title)
        .alert("Couldn't send request", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}

/// Kept so older call sites compile; it's the friend button now.
typealias FollowButton = FriendButton

/// Value over a small label, separated by hairlines when used in a row.
struct StatColumn: View {
    var value: String
    var label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).cvText(17, .bold, color: CV.text, inter: true).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).cvText(12, color: CV.muted, inter: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatRow: View {
    var items: [(String, String)]
    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                StatColumn(value: item.0, label: item.1)
                if i < items.count - 1 { Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 30) }
            }
        }
    }
}

/// Overlapping avatars ("rode with …").
struct AvatarStack: View {
    var riders: [RiderRef]
    var size: CGFloat = 26
    var body: some View {
        HStack(spacing: -8) {
            ForEach(riders.prefix(4), id: \.id) { r in
                AvatarChip(data: r.avatarData, name: r.name, size: size)
            }
        }
    }
}

struct CapsuleTag: View {
    var text: String
    var color: Color
    var dot = false
    var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(color).frame(width: 7, height: 7) }
            Text(text).cvText(11, .bold, color: color, tracking: 0.6, inter: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.16), in: Capsule())
    }
}

/// Text field style used in sheets (note to admin, comments, captions).
struct NoteField: View {
    var placeholder: String
    @Binding var text: String
    var limit: Int
    var minHeight: CGFloat = 84

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(CV.text.opacity(0.35)), axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(CV.text)
                .tint(CV.accent)
                .lineLimit(3...6)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                .onChange(of: text) { _, v in if v.count > limit { text = String(v.prefix(limit)) } }
            Text("\(text.count) / \(limit)").cvText(11, color: CV.dim, inter: true)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}
