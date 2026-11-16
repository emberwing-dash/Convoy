// CopyLinkRow.swift
// Tap-to-copy invite link / code, the same behaviour as the ride invite card:
// one tap puts it on the clipboard so it can be pasted into WhatsApp, Messages or the Join screen.
import SwiftUI

struct CopyLinkRow: View {
    /// What gets copied (a convoy:// link or a bare code).
    let value: String
    /// Optional big label shown above the link (e.g. the crew code).
    var title: String? = nil
    /// Text for the share sheet; nil hides the share button.
    var shareText: String? = nil

    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: copy) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let title {
                            Text(title).cvText(24, .bold, color: CV.text, tracking: 1.5, inter: true)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "link").font(.system(size: 11, weight: .medium))
                            Text(value).lineLimit(1).truncationMode(.middle)
                        }
                        .cvText(12, color: CV.muted, inter: true)
                        .foregroundStyle(CV.muted)
                    }
                    Spacer(minLength: 8)
                    Text(copied ? "Copied" : "Copy")
                        .cvText(14, .semibold, color: copied ? CV.onAccent : CV.text, inter: true)
                        .frame(width: 76, height: 36)
                        .background(copied ? CV.accent : CV.fill, in: Capsule())
                        .animation(.easeOut(duration: 0.15), value: copied)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied ? "Copied \(value)" : "Copy \(value)")

            if let shareText {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CV.onAccent)
                        .frame(width: 44, height: 44)
                        .background(CV.accent, in: Circle())
                }
                .accessibilityLabel("Share")
            }
        }
        .padding(16)
        .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(CV.stroke, lineWidth: 1))
    }

    private func copy() {
        UIPasteboard.general.string = value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            copied = false
        }
    }
}
