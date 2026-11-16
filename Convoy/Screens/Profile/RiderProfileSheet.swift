// RiderProfileSheet.swift
import SwiftUI

struct RiderProfileSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let riderId: UUID
    let fallback: ProfileRow
    @State private var profile: ProfileRow?
    @State private var isLoading = false

    private var displayName: String {
        let p = profile ?? fallback
        return p.display_name.isEmpty ? "@\(p.username)" : p.display_name
    }
    private var handle: String { (profile ?? fallback).username }
    private var avatarData: Data? {
        (profile ?? fallback).avatar_data.flatMap { Data(base64Encoded: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        AvatarChip(data: avatarData, name: displayName, size: 96)
                            .overlay(Circle().strokeBorder(CV.red, lineWidth: 2.5))
                        Text(displayName).cvText(22, .bold, tracking: -0.4, inter: true)
                        Text("@\(handle)").cvText(14, color: CV.muted, inter: true)
                    }.padding(.top, 24)

                    if app.backendUserId != riderId {
                        FollowButton(riderId: riderId).frame(maxWidth: 200)
                    }

                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").font(.system(size: 14)).foregroundStyle(CV.red)
                            Text("Rider on Convoy").cvText(14, .semibold, inter: true)
                        }
                        Text("Following riders shows you their rides and updates in your Feed.")
                            .cvText(12, color: CV.muted, inter: true)
                            .multilineTextAlignment(.center).padding(.horizontal, 20)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(CV.bg.ignoresSafeArea())
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(CV.red)
                }
            }.preferredColorScheme(.dark)
        }
        .task { await load() }
    }

    private func load() async {
        guard profile == nil else { return }
        isLoading = true
        if let p = try? await SupabaseManager.shared.fetchProfile(username: handle) {
            await MainActor.run { self.profile = p; self.isLoading = false }
        } else {
            await MainActor.run { self.isLoading = false }
        }
    }
}
