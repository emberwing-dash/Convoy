// ChatbotView.swift
import SwiftUI

struct ChatbotView: View {
    @Environment(AppState.self) private var app
    @State private var engine = ChatbotEngine()
    @State private var input = ""
    @FocusState private var focused: Bool
    @State private var ellisController = EllisController()
    @State private var hasCustomPosition = false

    // Typewriter state for welcome message
    @State private var typedWelcome = ""
    @State private var welcomeTypingDone = false

    // Track content area size for mascot positioning
    @State private var contentSize: CGSize = .zero

    private let starters: [(String, String)] = [
        ("Plan a ride to Munnar", "point.topleft.down.to.point.bottomright.curvepath"),
        ("Find a waterfall near Bangalore", "magnifyingglass"),
        ("What rides do I have?", "calendar"),
        ("Show me my crews", "person.3")
    ]

    private var welcomeFullText: String {
        "Hey \(app.displayName), I'm Ellis! What can I do for you?"
    }

    // Top-left position (below header)
    private func welcomePosition(size: CGSize) -> CGPoint {
        let half = mascotSizeForState / 2
        return CGPoint(x: half + 12, y: half + 8)
    }

    // Top-right mini position during chat
    private func chatPosition(size: CGSize) -> CGPoint {
        let half = mascotSizeForState / 2
        return CGPoint(x: size.width - half - 8, y: half + 8)
    }

    var body: some View {
        ZStack(alignment: .top) {
            CV.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if engine.rideDraft.isActive { progressBanner }

                GeometryReader { contentGeo in
                    ZStack(alignment: .topLeading) {
                        messagesScroll(contentGeo: contentGeo)

                        EllisMascot(
                            controller: ellisController,
                            size: mascotSizeForState,
                            onDraggedAway: { hasCustomPosition = true }
                        )
                    }
                    .onAppear {
                        contentSize = contentGeo.size
                        setupMascotBounds(size: contentGeo.size)
                        startWelcomeTyping()
                    }
                    .onChange(of: contentGeo.size) { _, newSize in
                        contentSize = newSize
                        setupMascotBounds(size: newSize)
                    }
                    .onChange(of: engine.messages.isEmpty) { _, isEmpty in
                        transitionMascotLayout(isWelcome: isEmpty, size: contentGeo.size)
                        if isEmpty { resetWelcomeTyping() }
                    }
                }

                inputBar
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onChange(of: engine.isThinking) { _, thinking in
            ellisController.onChatbotThinking(isThinking: thinking)
            if !thinking, let last = engine.messages.last, last.kind == .assistant {
                ellisController.onMessageReceived(last.text)
            }
        }
        .onChange(of: engine.rideDraft.isComplete) { _, isComplete in
            if isComplete { ellisController.onRidePlanCompleted() }
        }
        .onChange(of: engine.errorMessage) { _, err in
            if err != nil { ellisController.onChatbotError() }
        }
    }

    // MARK: - Typewriter Effect
    private func startWelcomeTyping() {
        typedWelcome = ""
        welcomeTypingDone = false
        let full = welcomeFullText
        let chars = Array(full)
        let charDelay = 0.028
        for (i, ch) in chars.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * charDelay) {
                guard !welcomeTypingDone else { return }
                typedWelcome.append(ch)
                if typedWelcome.count == chars.count { welcomeTypingDone = true }
            }
        }
    }

    private func resetWelcomeTyping() {
        welcomeTypingDone = false
        typedWelcome = ""
        startWelcomeTyping()
    }

    // MARK: - Mascot Layout Coordination
    private var mascotSizeForState: CGFloat {
        engine.messages.isEmpty ? 110.0 : 68.0
    }

    private func setupMascotBounds(size: CGSize) {
        guard size.width > 50 && size.height > 50 else { return }
        // Full content area — Ellis can go anywhere
        ellisController.dragBounds = CGRect(
            x: 0, y: 0, width: size.width, height: size.height
        )
        ellisController.defaultPosition = welcomePosition(size: size)

        if !hasCustomPosition {
            if engine.messages.isEmpty {
                ellisController.position = welcomePosition(size: size)
            } else {
                ellisController.position = chatPosition(size: size)
            }
        }
    }

    private func transitionMascotLayout(isWelcome: Bool, size: CGSize) {
        guard !hasCustomPosition else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            if isWelcome {
                ellisController.defaultPosition = welcomePosition(size: size)
                ellisController.position = welcomePosition(size: size)
            } else {
                ellisController.position = chatPosition(size: size)
            }
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 12) {
            CircleBackButton { app.pop() }
            Spacer()
            HStack(spacing: 10) {
                Image("ellis_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color(hex: 0xFF6B00).opacity(0.4), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ellis").cvText(16, .semibold, inter: true)
                    Text(rateLabel).cvText(11, color: rateColor, inter: true)
                }
            }
            Spacer()

            if hasMovedFromDefault {
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                        hasCustomPosition = false
                        ellisController.resetToDefaultPosition()
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(hex: 0xFF6B00).opacity(0.85))
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Reset Ellis Position")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 8)
    }

    private var hasMovedFromDefault: Bool {
        let def = ellisController.defaultPosition
        let cur = ellisController.position
        return hypot(cur.x - def.x, cur.y - def.y) > 24
    }

    private var rateLabel: String {
        if engine.promptsRemaining <= 0 { return "Limit reached · resets tomorrow" }
        return "\(engine.promptsRemaining)/50 prompts left today"
    }
    private var rateColor: Color {
        if engine.promptsRemaining <= 0 { return Color(hex: 0xFF5C00) }
        if engine.promptsRemaining <= 10 { return Color(hex: 0xFFB020) }
        return CV.cream.opacity(0.5)
    }

    private var progressBanner: some View {
        let draft = engine.rideDraft
        let collected = 3 - draft.missingFields.count
        let next = draft.missingFields.first.map(labelFor) ?? "Ready"
        return HStack(spacing: 8) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFF5C00))
            Text("Ride to \(draft.destination ?? "…")")
                .cvText(12, .semibold, inter: true)
            Text("· \(collected) of 3 details")
                .cvText(11, color: CV.cream.opacity(0.55), inter: true)
            Spacer()
            Text(next)
                .cvText(11, .medium, color: Color(hex: 0xFF5C00), inter: true)
        }
        .padding(.horizontal, 14).frame(height: 36)
        .background(Color(hex: 0xFF5C00).opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(hex: 0xFF5C00).opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 20).padding(.bottom, 8)
    }

    private func labelFor(_ field: String) -> String {
        switch field {
        case "destination": return "Destination"
        case "start":       return "Start point"
        case "time":        return "Start time"
        default:            return field
        }
    }

    // MARK: - Messages Scroll View
    private func messagesScroll(contentGeo: GeometryProxy) -> some View {
        // No top padding in welcome mode — Ellis overlaps top-left and bubble starts at top
        let topPad: CGFloat = engine.messages.isEmpty ? 6 : 8

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if engine.messages.isEmpty {
                        welcomeBlock(size: contentGeo.size)
                    }
                    ForEach(engine.messages) { msg in bubble(for: msg).id(msg.id) }
                    if engine.isThinking { thinkingBubble.id("thinking") }
                    if let err = engine.errorMessage { errorBubble(err).id("error") }
                    // Spacer at bottom so last message is never behind Ellis in chat mode
                    Color.clear.frame(height: engine.messages.isEmpty ? 0 : 88).id("bottom-spacer")
                }
                .padding(.horizontal, 20)
                .padding(.top, topPad)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: engine.messages.count) { _, _ in
                withAnimation(.snappy) {
                    proxy.scrollTo("bottom-spacer", anchor: .bottom)
                }
            }
            .onChange(of: engine.isThinking) { _, thinking in
                if thinking { withAnimation(.snappy) { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
            .onChange(of: engine.errorMessage) { _, err in
                if err != nil { withAnimation(.snappy) { proxy.scrollTo("error", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Welcome Block
    // Speech bubble at top, full width. Ellis floats top-left.
    // Tail points down-left toward Ellis mouth.
    private func welcomeBlock(size: CGSize) -> some View {
        let ellisMascotSize = mascotSizeForState  // 110pt
        // Left padding matches Ellis center so tail aligns visually with its mouth
        let tailLeadPad: CGFloat = ellisMascotSize * 0.42

        return VStack(alignment: .leading, spacing: 0) {
            // ── Message bubble (full width, sits right at top) ──
            VStack(alignment: .leading, spacing: 0) {
                Text(typedWelcome + (welcomeTypingDone ? "" : "▌"))
                    .cvText(15, lineHeight: 22, inter: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CV.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(CV.hairline, lineWidth: 1)
                    )

                // Tail pointing down-left toward Ellis
                HStack(spacing: 0) {
                    Color.clear.frame(width: tailLeadPad)
                    SpeechBubbleTailDown()
                        .fill(CV.surface)
                        .frame(width: 16, height: 10)
                    Spacer()
                }
            }

            // ── "Try one of these" + starters — immediately below bubble ──
            VStack(alignment: .leading, spacing: 8) {
                Text("Try one of these")
                    .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
                    .padding(.top, 16)

                VStack(spacing: 8) {
                    ForEach(Array(starters.enumerated()), id: \.offset) { _, item in
                        Button { input = item.0; focused = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.1)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0xFF5C00))
                                    .frame(width: 32, height: 32)
                                    .background(Color(hex: 0xFF5C00).opacity(0.12), in: Circle())
                                Text(item.0).cvText(14, .medium, inter: true).lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CV.cream.opacity(0.35))
                            }
                            .padding(.horizontal, 12).frame(height: 52)
                            .background(CV.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(CV.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .opacity(welcomeTypingDone ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: welcomeTypingDone)

                // Bottom reserve so Ellis doesn't sit over content
                Color.clear.frame(height: ellisMascotSize + 16)
            }
        }
    }

    // MARK: - Message Bubbles
    private func bubble(for msg: ChatMessage) -> some View {
        Group {
            switch msg.kind {
            case .user:
                HStack {
                    Spacer(minLength: 60)
                    Text(msg.text)
                        .cvText(15, color: CV.ink, lineHeight: 21, inter: true)
                        .padding(14)
                        .background(CV.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            case .assistant, .system:
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
                if let p = msg.pendingConfirmation { confirmationCard(p) }
                else {
                    HStack(alignment: .top, spacing: 12) {
                        assistantAvatar
                        Text(msg.text).cvText(15, lineHeight: 21, inter: true)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CV.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            case .error:
                HStack {
                    Text(msg.text).cvText(13, color: Color(hex: 0xFF5C00), inter: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xFF5C00).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func confirmationCard(_ p: PendingConfirmation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            assistantAvatar
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: p.isNavigating ? "arrow.up.forward.app" : "questionmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFFB020))
                    Text(p.displayTitle).cvText(15, .semibold, inter: true)
                }
                Text(p.displayDetail)
                    .cvText(13, color: CV.cream.opacity(0.7), lineHeight: 18, inter: true)
                    .lineLimit(4)
                HStack(spacing: 8) {
                    Button { Task { await engine.cancelPending(app: app) } } label: {
                        Text("Cancel").cvText(13, .semibold, color: CV.cream.opacity(0.75), inter: true)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }.buttonStyle(.plain)
                    Button { Task { await engine.confirmPending(app: app) } } label: {
                        Text(p.buttonLabel).cvText(13, .semibold, color: CV.ink, inter: true)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(CV.cream, in: Capsule())
                    }.buttonStyle(.plain)
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
                Text(text).cvText(13, color: CV.cream, lineHeight: 18, inter: true)
                Button { engine.clearError() } label: {
                    Text("Dismiss").cvText(12, .semibold, color: Color(hex: 0xFF5C00), inter: true)
                }.buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xFF5C00).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(hex: 0xFF5C00).opacity(0.3), lineWidth: 1))
        }
    }

    private var assistantAvatar: some View {
        Image("ellis_logo")
            .resizable()
            .scaledToFit()
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color(hex: 0xFF6B00).opacity(0.35), lineWidth: 1))
    }

    // MARK: - Input Composer
    private var inputBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("",
                          text: $input,
                          prompt: Text(engine.promptsRemaining > 0
                                       ? "Ask anything about rides, places, crews…"
                                       : "Daily limit reached")
                                    .foregroundColor(CV.cream.opacity(0.35)),
                          axis: .vertical)
                    .focused($focused)
                    .tint(Color(hex: 0xFF5C00))
                    .cvText(15, inter: true)
                    .lineLimit(1...4)
                    .disabled(engine.promptsRemaining == 0)
                    .onSubmit { send() }
                if !input.isEmpty {
                    Button { input = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(CV.cream.opacity(0.4))
                    }.buttonStyle(.plain)
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
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
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
        ellisController.onUserSentMessage()
        Task { await engine.send(text, app: app) }
    }
}

// MARK: - Speech Bubble Tail Shape
/// Downward-left pointing triangle — bubble is above Ellis
private struct SpeechBubbleTailDown: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // Top-left, top-right, bottom-middle (pointing down)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
