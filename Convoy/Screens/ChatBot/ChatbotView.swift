// ChatbotView.swift
import SwiftUI

struct ChatbotView: View {
    @Environment(AppState.self) private var app
    @State private var engine = ChatbotEngine()
    @State private var input = ""
    @FocusState private var focused: Bool

    private let starters: [(String, String)] = [
        ("Find a waterfall near Bangalore", "magnifyingglass"),
        ("Plan a ride to Munnar", "point.topleft.down.to.point.bottomright.curvepath"),
        ("What rides do I have?", "calendar"),
        ("Show me my crews", "person.3")
    ]

    var body: some View {
        ZStack(alignment: .top) {
            CV.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                messagesScroll
                inputBar
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            CircleBackButton { app.pop() }
            Spacer()
            VStack(spacing: 1) {
                Text("Convoy Assistant")
                    .cvText(16, .semibold, inter: true)
                Text(rateLabel)
                    .cvText(11, color: rateColor, inter: true)
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var rateLabel: String {
        if engine.promptsRemaining <= 0 { return "Limit reached · resets tomorrow" }
        return "\(engine.promptsRemaining)/50 prompts left today"
    }

    private var rateColor: Color {
        if engine.promptsRemaining <= 0 { return CV.red }
        if engine.promptsRemaining <= 10 { return Color(hex: 0xFFB020) }
        return CV.cream.opacity(0.5)
    }

    // MARK: - Messages

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if engine.messages.isEmpty {
                        welcomeBlock
                    }

                    ForEach(engine.messages) { msg in
                        bubble(for: msg).id(msg.id)
                    }

                    if engine.isThinking {
                        thinkingBubble.id("thinking")
                    }

                    if let err = engine.errorMessage {
                        errorBubble(err).id("error")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: engine.messages.count) { _, _ in
                withAnimation(.snappy) {
                    if let last = engine.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: engine.isThinking) { _, thinking in
                if thinking {
                    withAnimation(.snappy) { proxy.scrollTo("thinking", anchor: .bottom) }
                }
            }
            .onChange(of: engine.errorMessage) { _, err in
                if err != nil {
                    withAnimation(.snappy) { proxy.scrollTo("error", anchor: .bottom) }
                }
            }
        }
    }

    private var welcomeBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                assistantAvatar
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hey \(app.displayName), what can I do for you?")
                        .cvText(15, lineHeight: 21, inter: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CV.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(CV.hairline, lineWidth: 1))
                }
            }
            .padding(.top, 8)

            Text("Try one of these")
                .cvText(12, .semibold, color: CV.cream.opacity(0.5),
                        tracking: 0.6, inter: true)
                .padding(.leading, 46)

            VStack(spacing: 8) {
                ForEach(Array(starters.enumerated()), id: \.offset) { _, item in
                    Button { input = item.0; focused = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.1)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CV.red)
                                .frame(width: 32, height: 32)
                                .background(CV.red.opacity(0.12), in: Circle())
                            Text(item.0)
                                .cvText(14, .medium, inter: true)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CV.cream.opacity(0.35))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 52)
                        .background(CV.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(CV.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func bubble(for msg: ChatMessage) -> some View {
        Group {
            switch msg.kind {
            case .user:
                HStack {
                    Spacer(minLength: 40)
                    Text(msg.text)
                        .cvText(15, lineHeight: 21, inter: true)
                        .foregroundStyle(CV.ink)
                        .padding(14)
                        .background(CV.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            case .assistant:
                HStack(alignment: .top, spacing: 12) {
                    assistantAvatar
                    Text(msg.text)
                        .cvText(15, lineHeight: 21, inter: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CV.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(CV.hairline, lineWidth: 1))
                }
            case .confirmation:
                if let pending = msg.pendingConfirmation {
                    confirmationCard(pending)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        assistantAvatar
                        Text(msg.text)
                            .cvText(15, lineHeight: 21, inter: true)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CV.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            case .error:
                HStack {
                    Text(msg.text)
                        .cvText(13, color: CV.red, inter: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CV.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func confirmationCard(_ pending: PendingConfirmation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            assistantAvatar
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: pending.isNavigating ? "arrow.up.forward.app" : "questionmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFFB020))
                    Text(pending.displayTitle)
                        .cvText(15, .semibold, inter: true)
                }
                Text(pending.displayDetail)
                    .cvText(13, color: CV.cream.opacity(0.7), lineHeight: 18, inter: true)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Button {
                        Task { await engine.cancelPending(app: app) }
                    } label: {
                        Text("Cancel")
                            .cvText(13, .semibold, color: CV.cream.opacity(0.75), inter: true)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await engine.confirmPending(app: app) }
                    } label: {
                        Text(pending.buttonLabel)
                            .cvText(13, .semibold, color: CV.ink, inter: true)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(CV.cream, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color(hex: 0xFFB020).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(hex: 0xFFB020).opacity(0.3), lineWidth: 1))
        }
    }

    private var thinkingBubble: some View {
        HStack(alignment: .top, spacing: 12) {
            assistantAvatar
            HStack(spacing: 8) {
                ProgressView().tint(CV.cream).scaleEffect(0.8)
                Text(engine.thinkingStatus ?? "Thinking…")
                    .cvText(13, color: CV.cream.opacity(0.6), inter: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(CV.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer(minLength: 0)
        }
    }

    private func errorBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            assistantAvatar
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .cvText(13, color: CV.cream, lineHeight: 18, inter: true)
                Button { engine.clearError() } label: {
                    Text("Dismiss")
                        .cvText(12, .semibold, color: CV.red, inter: true)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CV.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CV.red.opacity(0.3), lineWidth: 1))
        }
    }

    private var assistantAvatar: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(CV.ink)
            .frame(width: 34, height: 34)
            .background(CV.red, in: Circle())
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("", text: $input,
                          prompt: Text(engine.promptsRemaining > 0
                                       ? "Ask anything about rides, places, crews…"
                                       : "Daily limit reached")
                                        .foregroundColor(CV.cream.opacity(0.35)),
                          axis: .vertical)
                    .focused($focused)
                    .tint(CV.red)
                    .cvText(15, inter: true)
                    .lineLimit(1...4)
                    .disabled(engine.promptsRemaining == 0)
                    .onSubmit { send() }

                if !input.isEmpty {
                    Button { input = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(CV.cream.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(CV.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(CV.hairline, lineWidth: 1))

            Button { send() } label: {
                Image(systemName: engine.isThinking ? "hourglass" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? CV.ink : CV.cream.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .background(canSend ? CV.cream : Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [CV.bg.opacity(0), CV.bg],
                           startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
        )
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !engine.isThinking
            && engine.promptsRemaining > 0
            && engine.pendingConfirmation == nil
    }

    private func send() {
        guard canSend else { return }
        let text = input
        input = ""
        focused = false
        Task { await engine.send(text, app: app) }
    }
}
