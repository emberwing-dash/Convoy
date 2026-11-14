import SwiftUI
import Combine

// MARK: - Ellis Mascot Controller
// Orchestrates physics, momentum dragging, edge collisions, tap reactions,
// autonomous idle behaviors, conversation lifecycle states, and context-aware reactions.

@MainActor
@Observable
public final class EllisController {

    // MARK: - Transform & Pose State
    public var expression: EllisExpression = .idle
    public var rotation: Double = 0.0              // Degrees
    public var squashX: CGFloat = 1.0              // Width scale
    public var squashY: CGFloat = 1.0              // Height scale
    public var offsetY: CGFloat = 0.0              // Vertical jump / float offset
    public var offsetX: CGFloat = 0.0              // Horizontal shake offset
    public var lookOffset: CGSize = .zero          // Gaze direction
    public var blinkProgress: CGFloat = 0.0        // Eyelid progress

    // MARK: - Dragging & Physics State
    public var position: CGPoint = .zero           // Current center position
    public var defaultPosition: CGPoint = .zero    // Resting welcome/dock position
    public var isDragging: Bool = false
    public var dragBounds: CGRect = .zero          // Usable bounding box
    public var mascotSize: CGFloat = 110.0
    public var currentPriority: Int = 0

    // MARK: - Configuration
    public var reduceMotion: Bool = false

    // MARK: - Internal Engine Mechanics
    private var velocity: CGVector = .zero
    private var dragStartPosition: CGPoint = .zero
    private var lastDragPoint: CGPoint = .zero
    private var lastDragTime: Date = Date()
    private var physicsTimer: Timer? = nil
    private var idleTimer: Timer? = nil
    private var floatTimer: Timer? = nil
    private var blinkTimer: Timer? = nil   // Dedicated natural blink timer
    private var floatPhase: Double = 0.0

    private var tapReactionIndex: Int = 0
    private var lastTapTime: Date = .distantPast
    private var lastCollisionTime: Date = .distantPast
    private var isRecovering: Bool = false

    // MARK: - Lifecycle
    public init() {}

    public func start() {
        startIdleScheduler()
        startFloatingLoop()
        startBlinkScheduler()
    }

    public func stop() {
        idleTimer?.invalidate()
        idleTimer = nil
        floatTimer?.invalidate()
        floatTimer = nil
        physicsTimer?.invalidate()
        physicsTimer = nil
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    // MARK: - Dedicated Natural Blink Scheduler
    // Fires independently of idle actions so Ellis always blinks naturally
    private func startBlinkScheduler() {
        scheduleNextBlink()
    }

    private func scheduleNextBlink() {
        // Natural human blink: every 2–7 seconds, varied
        let delay = Double.random(in: 2.5...7.0)
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Only blink if not already in a prioritized expression
                if self.currentPriority == 0 || self.currentPriority <= 10 {
                    // Occasionally do a double blink (25% chance)
                    if Double.random(in: 0...1) < 0.25 {
                        self.performDoubleBlink()
                    } else {
                        self.performBlink()
                    }
                }
                self.scheduleNextBlink()
            }
        }
    }

    // MARK: - Floating / Breathing Loop
    private func startFloatingLoop() {
        floatTimer?.invalidate()
        floatTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard !self.isDragging && self.expression == .idle && !self.isRecovering else { return }
                self.floatPhase += 0.045
                let breathe = sin(self.floatPhase) * (self.reduceMotion ? 1.0 : 3.0)
                self.offsetY = breathe
            }
        }
    }

    // MARK: - Drag Gesture Handling
    public func onDragStarted(at point: CGPoint) {
        physicsTimer?.invalidate()
        velocity = .zero
        dragStartPosition = position
        lastDragPoint = position
        lastDragTime = Date()
    }

    public func onDragConfirmed() {
        isDragging = true
        currentPriority = 100 // Drag is top priority
        physicsTimer?.invalidate()

        if !reduceMotion {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                squashX = 1.06
                squashY = 0.94
                rotation = 2.0
            }
        }
    }

    public func onDragChanged(translation: CGSize) {
        guard isDragging else { return }
        let now = Date()
        let dt = max(0.008, now.timeIntervalSince(lastDragTime))
        
        let newPos = CGPoint(
            x: dragStartPosition.x + translation.width,
            y: dragStartPosition.y + translation.height
        )

        // Calculate velocity (pt/s)
        let vx = (newPos.x - lastDragPoint.x) / CGFloat(dt)
        let vy = (newPos.y - lastDragPoint.y) / CGFloat(dt)
        velocity = CGVector(dx: vx, dy: vy)

        lastDragPoint = newPos
        lastDragTime = now

        // Check boundary limits and clamp
        let clampedPos = clampPositionToBounds(newPos)
        let hitEdge = (clampedPos != newPos)
        position = clampedPos

        // Check if fast drag hit an edge while dragging
        if hitEdge {
            let speed = hypot(velocity.dx, velocity.dy)
            checkAndTriggerCollision(speed: speed)
        }
    }

    public func onDragEnded(finalTranslation: CGSize) {
        isDragging = false
        
        // Settle pickup squash
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            squashX = 1.0
            squashY = 1.0
            rotation = 0.0
        }

        // Check flick momentum
        let speed = hypot(velocity.dx, velocity.dy)
        if speed > 80 {
            startMomentumPhysics()
        } else {
            currentPriority = 0
            softSettle()
        }
    }

    // MARK: - Momentum Physics & Boundary Bounce
    private func startMomentumPhysics() {
        physicsTimer?.invalidate()
        let friction: CGFloat = 0.92
        let minSpeed: CGFloat = 20.0

        physicsTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            // Capture timer reference safely to avoid Sendable warning
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                var curX = self.position.x + self.velocity.dx * 0.016
                var curY = self.position.y + self.velocity.dy * 0.016

                let half = self.mascotSize / 2
                var didCollide = false
                var impactSpeed: CGFloat = 0

                // X boundary bounce
                if curX - half < self.dragBounds.minX {
                    curX = self.dragBounds.minX + half
                    impactSpeed = abs(self.velocity.dx)
                    self.velocity.dx = -self.velocity.dx * 0.58
                    didCollide = true
                } else if curX + half > self.dragBounds.maxX {
                    curX = self.dragBounds.maxX - half
                    impactSpeed = abs(self.velocity.dx)
                    self.velocity.dx = -self.velocity.dx * 0.58
                    didCollide = true
                }

                // Y boundary bounce
                if curY - half < self.dragBounds.minY {
                    curY = self.dragBounds.minY + half
                    impactSpeed = max(impactSpeed, abs(self.velocity.dy))
                    self.velocity.dy = -self.velocity.dy * 0.58
                    didCollide = true
                } else if curY + half > self.dragBounds.maxY {
                    curY = self.dragBounds.maxY - half
                    impactSpeed = max(impactSpeed, abs(self.velocity.dy))
                    self.velocity.dy = -self.velocity.dy * 0.58
                    didCollide = true
                }

                self.position = CGPoint(x: curX, y: curY)

                if didCollide {
                    self.checkAndTriggerCollision(speed: impactSpeed)
                }

                // Apply friction
                self.velocity.dx *= friction
                self.velocity.dy *= friction

                let speed = hypot(self.velocity.dx, self.velocity.dy)
                if speed < minSpeed {
                    self.physicsTimer?.invalidate()
                    self.physicsTimer = nil
                    self.currentPriority = 0
                    self.softSettle()
                }
            }
        }
    }

    private func clampPositionToBounds(_ pos: CGPoint) -> CGPoint {
        guard dragBounds.width > mascotSize && dragBounds.height > mascotSize else { return pos }
        let half = mascotSize / 2
        let minX = dragBounds.minX + half
        let maxX = dragBounds.maxX - half
        let minY = dragBounds.minY + half
        let maxY = dragBounds.maxY - half

        return CGPoint(
            x: min(maxX, max(minX, pos.x)),
            y: min(maxY, max(minY, pos.y))
        )
    }

    // MARK: - Collision Detection & Pained Expression
    private func checkAndTriggerCollision(speed: CGFloat) {
        let now = Date()
        guard now.timeIntervalSince(lastCollisionTime) > 0.9 else { return } // Cooldown

        if speed > 700 {
            // HARD COLLISION -> Pained expression + recoil + shake
            lastCollisionTime = now
            triggerPainedCollisionReaction()
        } else if speed > 280 {
            // MEDIUM COLLISION -> Surprised recoil
            lastCollisionTime = now
            triggerSurprisedBounce()
        }
    }

    private func triggerPainedCollisionReaction() {
        currentPriority = 100 // Highest
        isRecovering = true
        expression = .pained

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        if !reduceMotion {
            // Squash on impact
            withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) {
                squashX = 1.25
                squashY = 0.78
                rotation = Double.random(in: -9...9)
            }

            // Quick shake
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.linear(duration: 0.06).repeatCount(4, autoreverses: true)) {
                    self.offsetX = 7.0
                }
            }
        }

        // Recover to normal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            self.expression = .recovering
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                self.offsetX = 0
                self.squashX = 1.0
                self.squashY = 1.0
                self.rotation = 0
            }
        }

        // Restore completely
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            self.expression = .idle
            self.isRecovering = false
            self.currentPriority = 0
        }
    }

    private func triggerSurprisedBounce() {
        guard currentPriority <= 85 else { return }
        currentPriority = 85
        expression = .surprised

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        if !reduceMotion {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                squashX = 1.12
                squashY = 0.88
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.squashX = 1.0
                self.squashY = 1.0
            }
            self.expression = .idle
            self.currentPriority = 0
        }
    }

    // MARK: - Tap Interactions (Varied Playful Reactions)
    public func onTap() {
        let now = Date()
        guard now.timeIntervalSince(lastTapTime) > 0.4 else { return }
        lastTapTime = now
        guard currentPriority <= 80 else { return }

        tapReactionIndex = (tapReactionIndex + 1) % 6
        currentPriority = 80

        let haptic = UISelectionFeedbackGenerator()
        haptic.selectionChanged()

        switch tapReactionIndex {
        case 0:
            // 1. Surprised reaction followed by a small jump
            expression = .surprised
            if !reduceMotion {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
                    offsetY = -18
                    squashX = 0.94
                    squashY = 1.08
                }
            }
            scheduleRestore(after: 0.45)

        case 1:
            // 2. Playful annoyed expression + small shake
            expression = .angry
            if !reduceMotion {
                withAnimation(.linear(duration: 0.06).repeatCount(4, autoreverses: true)) {
                    offsetX = 6
                    rotation = 6
                }
            }
            scheduleRestore(after: 0.50)

        case 2:
            // 3. Quick 360-degree spin
            expression = .excited
            if !reduceMotion {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                    rotation += 360
                    offsetY = -12
                }
            }
            scheduleRestore(after: 0.55)

        case 3:
            // 4. Happy double jump
            expression = .happy
            if !reduceMotion {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                    offsetY = -16
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                        self.offsetY = -20
                    }
                }
            }
            scheduleRestore(after: 0.58)

        case 4:
            // 5. Curious head tilt
            expression = .confused
            if !reduceMotion {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    rotation = 14
                    lookOffset = CGSize(width: -4, height: -2)
                }
            }
            scheduleRestore(after: 0.50)

        default:
            // 6. Playful bounce & celebration
            expression = .celebrating
            if !reduceMotion {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) {
                    squashX = 1.15
                    squashY = 0.85
                    offsetY = -14
                }
            }
            scheduleRestore(after: 0.48)
        }
    }

    // MARK: - Conversation Lifecycle Bindings
    public func onUserSentMessage() {
        guard currentPriority <= 70 else { return }
        currentPriority = 70
        expression = .listening
        if !reduceMotion {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                rotation = -4
                offsetY = -6
            }
        }
        scheduleRestore(after: 1.0)
    }

    public func onChatbotThinking(isThinking: Bool) {
        if isThinking {
            guard currentPriority <= 75 else { return }
            currentPriority = 75
            expression = .thinking
            lookOffset = CGSize(width: 4, height: -4)
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.3)) {
                    rotation = 6
                }
            }
        } else {
            if expression == .thinking {
                expression = .speaking
                scheduleRestore(after: 0.8)
            }
        }
    }

    public func onRidePlanCompleted() {
        guard currentPriority <= 85 else { return }
        currentPriority = 85
        expression = .celebrating
        if !reduceMotion {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                offsetY = -24
                rotation = 8
            }
        }
        scheduleRestore(after: 1.2)
    }

    public func onChatbotError() {
        guard currentPriority <= 65 else { return }
        currentPriority = 65
        expression = .confused
        if !reduceMotion {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                rotation = -8
            }
        }
        scheduleRestore(after: 1.0)
    }

    // MARK: - Context-Aware Conversation Reactions (Section 9)
    /// Set by ChatbotView to tell Ellis where the most recent message bubble is
    public var nearMessageTarget: CGPoint? = nil

    /// Analyzes an incoming assistant message and triggers an appropriate
    /// emotional reaction based on keywords and sentiment.
    /// Also drifts Ellis slowly toward the latest message bubble.
    public func onMessageReceived(_ text: String) {
        guard currentPriority <= 60 else { return }
        let lower = text.lowercased()

        // Drift Ellis slowly toward the message bubble (top ~30% of chat area)
        driftNearMessage()

        // Celebratory / positive
        if matchesAny(lower, ["congratulations", "awesome", "perfect", "ride created",
                              "all set", "let's go", "you're all set", "great news",
                              "successfully", "booked", "confirmed"]) {
            triggerContextReaction(.happy, priority: 65, duration: 1.0, jump: -10, tilt: 5)
            return
        }

        // Excited / enthusiastic
        if matchesAny(lower, ["amazing", "incredible", "beautiful route", "scenic",
                              "waterfall", "epic", "breathtaking", "stunning"]) {
            triggerContextReaction(.excited, priority: 65, duration: 0.9, jump: -14, tilt: 4)
            return
        }

        // Error / problem
        if matchesAny(lower, ["sorry", "couldn't", "error", "failed", "unable",
                              "not found", "issue", "problem", "unfortunately"]) {
            triggerContextReaction(.confused, priority: 60, duration: 0.9, jump: 0, tilt: -8)
            return
        }

        // Question / clarification
        if matchesAny(lower, ["which", "where would", "do you want", "would you like",
                              "can you tell", "what time", "how many", "could you"]) {
            triggerContextReaction(.listening, priority: 60, duration: 0.8, jump: -4, tilt: -4)
            return
        }

        // Thinking / working
        if matchesAny(lower, ["let me check", "searching", "looking up", "finding",
                              "calculating", "one moment"]) {
            triggerContextReaction(.thinking, priority: 60, duration: 0.7, jump: 0, tilt: 6)
            return
        }

        // Friendly greeting
        if matchesAny(lower, ["hey", "hello", "hi there", "good morning", "good evening",
                              "welcome back", "nice to see"]) {
            triggerContextReaction(.happy, priority: 60, duration: 0.8, jump: -8, tilt: 3)
            return
        }

        // Farewell
        if matchesAny(lower, ["ride safe", "see you", "goodbye", "take care",
                              "have a great ride", "safe travels"]) {
            triggerContextReaction(.happy, priority: 60, duration: 1.0, jump: -6, tilt: 0)
            return
        }
    }

    /// Smoothly drifts Ellis toward the top-right area where messages appear,
    /// keeping a safe gap so it doesn't sit on top of the text.
    private func driftNearMessage() {
        guard !isDragging else { return }
        // Target: upper-right of content area, next to the assistant avatar row
        // We use a fraction of dragBounds — right side, upper third
        guard dragBounds.width > 60 && dragBounds.height > 60 else { return }
        let half = mascotSize / 2
        let targetX = dragBounds.maxX - half - 4   // right edge
        let targetY = dragBounds.minY + half + 8   // near top
        let target = CGPoint(x: targetX, y: targetY)

        // Only drift if not already close
        let dist = hypot(position.x - target.x, position.y - target.y)
        guard dist > 20 else { return }

        withAnimation(.easeInOut(duration: 0.9)) {
            position = target
        }
    }

    private func matchesAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private func triggerContextReaction(_ expr: EllisExpression, priority: Int, duration: Double, jump: CGFloat, tilt: Double) {
        currentPriority = priority
        expression = expr

        if !reduceMotion {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                if jump != 0 { offsetY = jump }
                if tilt != 0 { rotation = tilt }
            }
        }
        scheduleRestore(after: duration)
    }

    // MARK: - Autonomous Idle System
    private func startIdleScheduler() {
        scheduleNextIdleAction()
    }

    private func scheduleNextIdleAction() {
        let delay = Double.random(in: 3.2...6.8)
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.performRandomIdleAction()
                self.scheduleNextIdleAction()
            }
        }
    }

    private func performRandomIdleAction() {
        guard currentPriority == 0 && !isDragging && !isRecovering else { return }

        let roll = Int.random(in: 0...10)
        switch roll {
        case 0, 1, 2, 3:
            // Natural blink
            performBlink()
        case 4:
            // Double blink
            performDoubleBlink()
        case 5:
            // Glance left
            glance(offset: CGSize(width: -6, height: 0), expr: .lookLeft)
        case 6:
            // Glance right
            glance(offset: CGSize(width: 6, height: 0), expr: .lookRight)
        case 7:
            // Glance up
            glance(offset: CGSize(width: 0, height: -5), expr: .lookUp)
        case 8:
            // Subtle head tilt
            tiltHead()
        case 9:
            // Small playful hop
            if !reduceMotion {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    offsetY = -10
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.softSettle()
                }
            }
        default:
            performBlink()
        }
    }

    private func performBlink() {
        withAnimation(.easeInOut(duration: 0.10)) { blinkProgress = 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 0.10)) { self.blinkProgress = 0.0 }
        }
    }

    private func performDoubleBlink() {
        performBlink()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            self.performBlink()
        }
    }

    private func glance(offset: CGSize, expr: EllisExpression) {
        expression = expr
        withAnimation(.easeInOut(duration: 0.2)) { lookOffset = offset }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.lookOffset = .zero
                self.expression = .idle
            }
        }
    }

    private func tiltHead() {
        let angle = Double.random(in: 0...1) > 0.5 ? 9.0 : -9.0
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            rotation = angle
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                self.rotation = 0.0
            }
        }
    }

    // MARK: - State Restoration & Settling
    private func scheduleRestore(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.softSettle()
        }
    }

    public func softSettle() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) {
            rotation = 0.0
            squashX = 1.0
            squashY = 1.0
            offsetX = 0.0
            offsetY = 0.0
            lookOffset = .zero
            blinkProgress = 0.0
        }
        expression = .idle
        currentPriority = 0
    }

    /// Reset position to default welcome position
    public func resetToDefaultPosition() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            position = defaultPosition
            rotation = 0
            squashX = 1.0
            squashY = 1.0
            offsetX = 0
            offsetY = 0
        }
        softSettle()
    }
}
