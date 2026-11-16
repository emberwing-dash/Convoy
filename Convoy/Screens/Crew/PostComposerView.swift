// PostComposerView.swift
import SwiftUI

struct PostComposerView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    enum PostKind: String, CaseIterable { case update, experience
        var title: String { self == .update ? "Update" : "Experience" }
    }

    @State private var kind: PostKind = .update
    @State private var title = ""
    @State private var body_ = ""
    @State private var visibility: String = "public"
    @State private var selectedRideId: UUID?
    @State private var isPosting = false
    @State private var errorMessage: String?

    private var selectedRide: Ride? {
        guard let id = selectedRideId else { return nil }
        return app.rides.first { $0.id == id }
    }

    private var canPost: Bool {
        !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPosting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    kindPicker
                    titleField
                    bodyEditor
                    linkRideSection
                    visibilityPicker
                    if let e = errorMessage {
                        Text(e).cvText(13, color: CV.red, inter: true)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .background(CV.bg.ignoresSafeArea())
            .navigationTitle("New post").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(CV.cream.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await post() }
                    } label: {
                        if isPosting {
                            ProgressView().tint(CV.red).scaleEffect(0.8)
                        } else {
                            Text("Post").font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(canPost ? CV.red : CV.muted)
                        }
                    }.disabled(!canPost)
                }
            }.preferredColorScheme(.dark)
        }
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(PostKind.allCases, id: \.self) { k in
                Button { kind = k } label: {
                    Text(k.title).cvText(13, .medium,
                                         color: kind == k ? CV.ink : CV.cream, inter: true)
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(kind == k ? CV.cream : Color.white.opacity(0.06),
                                    in: Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title").cvText(12, .semibold, color: CV.muted, tracking: 0.6, inter: true)
            TextField("", text: $title,
                      prompt: Text("Optional — e.g. Coorg weekend").foregroundColor(CV.cream.opacity(0.4)))
                .tint(CV.red).cvText(15, inter: true)
                .padding(.horizontal, 14).frame(height: 50)
                .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What happened?").cvText(12, .semibold, color: CV.muted, tracking: 0.6, inter: true)
            TextEditor(text: $body_)
                .tint(CV.red).cvText(15, inter: true)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120).padding(10)
                .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private var linkRideSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Link a ride").cvText(12, .semibold, color: CV.muted, tracking: 0.6, inter: true)
            Menu {
                Button("None") { selectedRideId = nil }
                if !app.rides.isEmpty {
                    Divider()
                    ForEach(app.rides) { r in
                        Button(r.title) { selectedRideId = r.id }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundStyle(CV.red)
                    Text(selectedRide?.title ?? "None")
                        .cvText(15, .medium, color: CV.cream, inter: true).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.muted)
                }
                .padding(.horizontal, 14).frame(height: 50)
                .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
    }

    private var visibilityPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Who can see this?").cvText(12, .semibold, color: CV.muted, tracking: 0.6, inter: true)
            HStack(spacing: 0) {
                visOption("Public", value: "public")
                visOption("Followers", value: "followers")
            }
            .padding(4).frame(height: 40)
            .background(Color(hex: 0x1A1A1D), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func visOption(_ title: String, value: String) -> some View {
        let on = visibility == value
        return Button { visibility = value } label: {
            Text(title).cvText(13, .semibold,
                               color: on ? CV.ink : CV.cream.opacity(0.6), inter: true)
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(on ? CV.cream : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func post() async {
        guard let me = await app.resolvedUserId() else {
            errorMessage = "You're not signed in."
            return
        }
        await MainActor.run { isPosting = true; errorMessage = nil }

        let body = body_.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let insert = PostInsert(
            author_id: me,
            kind: kind == .update ? "update" : "experience",
            visibility: visibility,
            crew_id: nil,
            ride_id: selectedRideId,
            title: t.isEmpty ? nil : t,
            body: body.isEmpty ? nil : body,
            media_json: "[]",
            route_km: selectedRide?.plan.selected?.km,
            route_from: selectedRide?.plan.from,
            route_to: selectedRide?.plan.to
        )

        do {
            _ = try await SupabaseManager.shared.createPost(insert)
            await MainActor.run {
                isPosting = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                isPosting = false
                errorMessage = "Couldn't post: \(error.localizedDescription)"
            }
        }
    }
}
