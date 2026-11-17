// ChatbotView.swift
import SwiftUI

struct ChatbotView: View {
    @Environment(AppState.self) private var app
    @State private var engine = ChatbotEngine()
    @State private var backendLabel = ChatbotBackend.current.rawValue.uppercased()
    @State private var input = ""
    @FocusState private var focused: Bool
    @State private var ellisController = EllisController()
    @State private var hasCustomPosition = false
    @AppStorage(ChatTheme.storageKey) private var themeRaw = ChatTheme.ember.rawValue
    @State private var showEllisSheet = false
    private var theme: ChatTheme { ChatTheme.load(themeRaw) }

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
            ChatTopGlow(theme: theme)
            VStack(spacing: 0) {
                header
                ZStack(alignment: .top) {
                VStack(spacing: 0) {
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
                    if showEllisSheet { ellisSheetLayer }
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        // Pick up the operator's V1/V2 switch (app_config) each time the chat opens.
        .task { await ChatbotBackend.refresh(userId: app.backendUserId); backendLabel = ChatbotBackend.current.rawValue.uppercased() }
        // Back from the planner: if the ride was created there, close the plan in the chat.
        .onAppear { engine.noteRideCreatedIfNeeded(app: app) }
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
                Button { toggleEllisSheet() } label: {
                    HStack(spacing: 10) {
                        Image("ellis_logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(theme.accent.opacity(0.6), lineWidth: 1.5))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("Ellis").cvText(16, .semibold, inter: true)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(CV.text.opacity(0.6))
                                    .rotationEffect(.degrees(showEllisSheet ? 180 : 0))
                            }
                            Text(rateLabel).cvText(11, color: rateColor, inter: true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ellis options")
                .accessibilityHint("Change the chat colour or start a new chat")
                #if DEBUG
                // Test switch (Debug builds only): long-press to cycle Remote → V1 → V2.
                Text(backendLabel)
                    .cvText(10, .bold, color: backendLabel == "V2" ? CV.green : CV.muted, inter: true)
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .onLongPressGesture {
                        switch ChatbotBackend.debugOverride {
                        case nil: ChatbotBackend.debugOverride = .v1
                        case .v1: ChatbotBackend.debugOverride = .v2
                        case .v2: ChatbotBackend.debugOverride = nil
                        }
                        let o = ChatbotBackend.debugOverride
                        backendLabel = o == nil ? "\(ChatbotBackend.current.rawValue.uppercased())·R" : o!.rawValue.uppercased()
                    }
                    .accessibilityLabel("Chatbot backend \(backendLabel)")
                #endif
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
                        .foregroundStyle(theme.accent.opacity(0.9))
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
        return "\(engine.promptsRemaining)/9999 prompts left today"
    }
    private var rateColor: Color {
        if engine.promptsRemaining <= 0 { return CV.accent }
        if engine.promptsRemaining <= 10 { return CV.warning }
        return CV.text.opacity(0.5)
    }

    private var progressBanner: some View {
        let draft = engine.rideDraft
        let collected = 3 - draft.missingFields.count
        let next = draft.missingFields.first.map(labelFor) ?? "Ready"
        return HStack(spacing: 8) {
            IconBadge(symbol: "point.topleft.down.to.point.bottomright.curvepath", color: theme.accent, size: 24)
            Text("Ride to \(draft.destination ?? "…")")
                .cvText(12, .semibold, inter: true)
                .lineLimit(1)
            Text("· \(collected) of 3 details")
                .cvText(11, color: CV.text.opacity(0.55), inter: true)
            Spacer()
            if draft.isComplete {
                // The plan is kept after visiting the planner — reopen review in one tap.
                Button { Task { await engine.reopenReview(app: app) } } label: {
                    HStack(spacing: 4) {
                        Text("Review").cvText(12, .bold, color: CV.onAccent, inter: true)
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(CV.onAccent)
                    }
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(engine.isThinking)
                .accessibilityLabel("Open ride review")
            } else {
                Text(next)
                    .cvText(11, .medium, color: theme.accent, inter: true)
            }
        }
        .padding(.leading, 6).padding(.trailing, draft.isComplete ? 5 : 14).frame(height: 36)
        .background(.ultraThinMaterial, in: Capsule())
        .background(theme.accent.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(theme.accent.opacity(0.35), lineWidth: 1))
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
            .onAppear {
                if let last = engine.messages.last {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
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
                    .cvText(12, .semibold, color: CV.text.opacity(0.5), tracking: 0.6, inter: true)
                    .padding(.top, 16)

                VStack(spacing: 8) {
                    ForEach(Array(starters.enumerated()), id: \.offset) { _, item in
                        Button { input = item.0; focused = true } label: {
                            HStack(spacing: 10) {
                                IconBadge(symbol: item.1, size: 34)
                                Text(item.0).cvText(14, .medium, inter: true).lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CV.text.opacity(0.35))
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

    /// List items in the latest answer can be tapped to reply with them; older answers are read-only.
    private func pickHandler(for msg: ChatMessage) -> ((String) -> Void)? {
        guard msg.id == engine.messages.last(where: { $0.kind == .assistant })?.id,
              msg.id == engine.messages.last?.id else { return nil }
        return { title in
            guard !engine.isThinking, engine.pendingConfirmation == nil else { return }
            ellisController.onUserSentMessage()
            Task { await engine.send(title, app: app) }
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
                        .cvText(15, color: CV.onAccent, lineHeight: 21, inter: true)
                        .padding(14)
                        .background(theme.bubble, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            case .assistant, .system:
                HStack(alignment: .top, spacing: 12) {
                    assistantAvatar
                    ChatAnswerView(text: msg.text, onPick: pickHandler(for: msg), tint: theme.accent)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pxCard(radius: 16, tint: theme.accent)
                }
            case .confirmation:
                if let p = msg.pendingConfirmation { confirmationCard(p) }
                else if msg.action == "finalize_ride_plan" { reviewOpenedCard(msg) }
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
                    Text(msg.text).cvText(13, color: CV.accent, inter: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CV.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func confirmationCard(_ p: PendingConfirmation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            assistantAvatar
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    IconBadge(symbol: p.isNavigating ? "map.fill" : "questionmark.circle.fill",
                              color: p.isNavigating ? theme.accent : Hue.honey, size: 28)
                    Text(p.displayTitle).cvText(15, .semibold, inter: true)
                }
                Text(p.displayDetail)
                    .cvText(13, color: CV.text.opacity(0.7), lineHeight: 18, inter: true)
                    .lineLimit(4)
                HStack(spacing: 8) {
                    Button { Task { await engine.cancelPending(app: app) } } label: {
                        Text("Cancel").cvText(13, .semibold, color: CV.text.opacity(0.75), inter: true)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }.buttonStyle(.plain)
                    Button { Task { await engine.confirmPending(app: app) } } label: {
                        Text(p.buttonLabel).cvText(13, .semibold, color: CV.onAccent, inter: true)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(theme.accent, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(14)
            .pxCard(radius: 16, tint: theme.accent)
        }
    }

    /// A confirmed "Open ride review" card. While the plan is still open, the latest one keeps a
    /// button to open the review again (after Edit route → back to chat).
    private func reviewOpenedCard(_ msg: ChatMessage) -> some View {
        let isLatest = msg.id == engine.messages.last(where: { $0.action == "finalize_ride_plan" })?.id
        let canReopen = isLatest && engine.rideDraft.isComplete
        return HStack(alignment: .top, spacing: 12) {
            assistantAvatar
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    IconBadge(symbol: "checkmark.circle.fill", color: Hue.sage, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(msg.text).cvText(15, .semibold, inter: true)
                        if let dest = engine.rideDraft.destination, canReopen {
                            Text("Ride to \(dest)").cvText(12, color: CV.text.opacity(0.6), inter: true)
                        }
                    }
                }
                if canReopen {
                    Button { Task { await engine.reopenReview(app: app) } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "map.fill").font(.system(size: 12, weight: .semibold))
                            Text("Open ride review").cvText(13, .semibold, color: CV.onAccent, inter: true)
                        }
                        .foregroundStyle(CV.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(theme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.isThinking)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pxCard(radius: 16, tint: Hue.sage)
        }
    }

    // MARK: - Ellis sheet (drops down from the title)

    private func toggleEllisSheet() {
        focused = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { showEllisSheet.toggle() }
    }

    private var ellisSheetLayer: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45)
                .ignoresSafeArea(edges: .bottom)
                .onTapGesture { toggleEllisSheet() }
                .transition(.opacity)
            ellisSheet
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var ellisSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image("ellis_logo").resizable().scaledToFit()
                    .frame(width: 44, height: 44).clipShape(Circle())
                    .overlay(Circle().strokeBorder(theme.accent.opacity(0.7), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ellis").cvText(17, .bold, inter: true)
                    Text("Your ride assistant").cvText(12, color: CV.text.opacity(0.6), inter: true)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("CHAT COLOUR").cvText(11, .semibold, color: CV.text.opacity(0.5), tracking: 0.8, inter: true)
                HStack(spacing: 0) {
                    ForEach(ChatTheme.allCases) { t in
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { themeRaw = t.rawValue }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(t.swatch).frame(width: 36, height: 36)
                                    if t == theme {
                                        Circle().strokeBorder(Color.white, lineWidth: 2).frame(width: 44, height: 44)
                                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(t == .graphite ? CV.onAccent : .white)
                                    }
                                }
                                .frame(width: 46, height: 46)
                                Text(t.name).cvText(10.5, t == theme ? .semibold : .regular,
                                                    color: CV.text.opacity(t == theme ? 1 : 0.6), inter: true)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(t.name) colour")
                        .accessibilityAddTraits(t == theme ? .isSelected : [])
                    }
                }
            }

            Rectangle().fill(CV.hairline).frame(height: 1)

            Button {
                engine.startNewChat()
                hasCustomPosition = false
                toggleEllisSheet()
            } label: {
                HStack(spacing: 12) {
                    IconBadge(symbol: "square.and.pencil", color: Hue.periwinkle, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New chat").cvText(14, .semibold, inter: true)
                        Text("Clears this conversation and any ride plan in it")
                            .cvText(11.5, color: CV.text.opacity(0.55), inter: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CV.text.opacity(0.35))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(engine.isThinking || engine.messages.isEmpty)
            .opacity(engine.messages.isEmpty ? 0.5 : 1)
        }
        .padding(16)
        .pxCard(radius: 24, tint: theme.accent)
        .background(Color(hex: 0x131316), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
    }

    private var thinkingBubble: some View {
        HStack(alignment: .top, spacing: 12) {
            assistantAvatar
            HStack(spacing: 8) {
                ProgressView().tint(theme.accent).scaleEffect(0.8)
                Text(engine.thinkingStatus ?? "Thinking…")
                    .cvText(13, color: CV.text.opacity(0.6), inter: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .pxCard(radius: 16, tint: theme.accent)
            Spacer(minLength: 0)
        }
    }

    private func errorBubble(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            assistantAvatar
            VStack(alignment: .leading, spacing: 8) {
                Text(text).cvText(13, color: CV.text, lineHeight: 18, inter: true)
                HStack(spacing: 16) {
                    if engine.failedUserText != nil {
                        Button { Task { await engine.retryLastFailed(app: app) } } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CV.accent)
                        }.buttonStyle(.plain)
                    }
                    Button { engine.clearError() } label: {
                        Text("Dismiss").cvText(12, .semibold, color: CV.accent, inter: true)
                    }.buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CV.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CV.accent.opacity(0.3), lineWidth: 1))
        }
    }

    private var assistantAvatar: some View {
        Image("ellis_logo")
            .resizable()
            .scaledToFit()
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(theme.accent.opacity(0.55), lineWidth: 1.5))
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
                                    .foregroundColor(CV.text.opacity(0.35)),
                          axis: .vertical)
                    .focused($focused)
                    .tint(theme.accent)
                    .cvText(15, inter: true)
                    .lineLimit(1...4)
                    .disabled(engine.promptsRemaining == 0)
                    .onSubmit { send() }
                if !input.isEmpty {
                    Button { input = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(CV.text.opacity(0.4))
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
                    .foregroundStyle(canSend ? CV.onAccent : CV.text.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .background(canSend ? AnyShapeStyle(theme.bubble) : AnyShapeStyle(Color.white.opacity(0.08)), in: Circle())
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
