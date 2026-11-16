
import SwiftUI
import Combine

@MainActor
@Observable
public final class EllisController {

    // MARK: - Mascot State

    public var expression: EllisExpression = .idle
    public var rotation: Double = 0
    public var squashX: CGFloat = 1
    public var squashY: CGFloat = 1
    public var offsetY: CGFloat = 0
    public var offsetX: CGFloat = 0
    public var lookOffset: CGSize = .zero
    public var blinkProgress: CGFloat = 0

    // MARK: - Position and Dragging

    public var position: CGPoint = .zero
    public var defaultPosition: CGPoint = .zero
    public var isDragging = false
    public var dragBounds: CGRect = .zero
    public var mascotSize: CGFloat = 110
    public var currentPriority = 0

    public var reduceMotion = false
    public var nearMessageTarget: CGPoint? = nil

    // MARK: - Internal State

    private var velocity: CGVector = .zero
    private var dragStartPosition: CGPoint = .zero
    private var lastDragPoint: CGPoint = .zero
    private var lastDragTime = Date()

    private var physicsTimer: Timer?
    private var idleTimer: Timer?
    private var floatTimer: Timer?
    private var blinkTimer: Timer?

    private var floatPhase: Double = 0
    private var tapReactionIndex = 0
    private var lastTapTime = Date.distantPast
    private var lastCollisionTime = Date.distantPast

    private var isRecovering = false
    private var chatbotIsThinking = false

    private var actionGeneration = 0
    private var restoreWorkItem: DispatchWorkItem?

    // MARK: - Initialization

    public init() {}

    // MARK: - Lifecycle

    public func start() {
        startIdleScheduler()
        startFloatingLoop()
        startBlinkScheduler()
    }

    public func stop() {
        idleTimer?.invalidate()
        floatTimer?.invalidate()
        physicsTimer?.invalidate()
        blinkTimer?.invalidate()

        idleTimer = nil
        floatTimer = nil
        physicsTimer = nil
        blinkTimer = nil

        invalidateScheduledRestore()
    }

    // MARK: - Animation Priority

    private func invalidateScheduledRestore() {
        actionGeneration += 1
        restoreWorkItem?.cancel()
        restoreWorkItem = nil
    }

    private func scheduleRestore(after delay: Double) {
        invalidateScheduledRestore()

        let generation = actionGeneration

        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.actionGeneration == generation,
                  !self.isDragging
            else {
                return
            }

            self.restoreWorkItem = nil
            self.softSettle()
        }

        restoreWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: work
        )
    }

    // MARK: - Dragging

    public func onDragStarted(at point: CGPoint) {
        invalidateScheduledRestore()

        physicsTimer?.invalidate()
        physicsTimer = nil

        velocity = .zero
        dragStartPosition = position
        lastDragPoint = position
        lastDragTime = Date()
    }

    public func onDragConfirmed() {
        invalidateScheduledRestore()

        isDragging = true
        currentPriority = 100

        physicsTimer?.invalidate()
        physicsTimer = nil

        if !reduceMotion {
            withAnimation(
                .spring(response: 0.25, dampingFraction: 0.6)
            ) {
                squashX = 1.06
                squashY = 0.94
                rotation = 2
            }
        }
    }

    public func onDragChanged(translation: CGSize) {
        guard isDragging else { return }

        let now = Date()
        let dt = max(0.008, now.timeIntervalSince(lastDragTime))

        let newPosition = CGPoint(
            x: dragStartPosition.x + translation.width,
            y: dragStartPosition.y + translation.height
        )

        velocity = CGVector(
            dx: (newPosition.x - lastDragPoint.x) / CGFloat(dt),
            dy: (newPosition.y - lastDragPoint.y) / CGFloat(dt)
        )

        lastDragPoint = newPosition
        lastDragTime = now

        let clamped = clampPosition(newPosition)
        position = clamped

        if clamped != newPosition {
            checkAndTriggerCollision(
                speed: hypot(velocity.dx, velocity.dy)
            )
        }
    }

    public func onDragEnded(finalTranslation: CGSize) {
        isDragging = false

        withAnimation(
            .spring(response: 0.35, dampingFraction: 0.7)
        ) {
            squashX = 1
            squashY = 1
            rotation = 0
        }

        let speed = hypot(velocity.dx, velocity.dy)

        if speed > 80 {
            startMomentumPhysics()
        } else {
            currentPriority = chatbotIsThinking ? 75 : 0
            softSettle()
        }
    }

    private func clampPosition(_ point: CGPoint) -> CGPoint {
        guard dragBounds.width > mascotSize,
              dragBounds.height > mascotSize
        else {
            return point
        }

        let half = mascotSize / 2

        return CGPoint(
            x: min(
                max(point.x, dragBounds.minX + half),
                dragBounds.maxX - half
            ),
            y: min(
                max(point.y, dragBounds.minY + half),
                dragBounds.maxY - half
            )
        )
    }

    // MARK: - Momentum Physics

    private func startMomentumPhysics() {
        physicsTimer?.invalidate()

        let friction: CGFloat = 0.92
        let minimumSpeed: CGFloat = 20

        physicsTimer = Timer.scheduledTimer(
            withTimeInterval: 0.016,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isDragging else { return }

                var x = self.position.x + self.velocity.dx * 0.016
                var y = self.position.y + self.velocity.dy * 0.016

                let half = self.mascotSize / 2
                var collisionSpeed: CGFloat = 0
                var collided = false

                if x - half < self.dragBounds.minX {
                    x = self.dragBounds.minX + half
                    collisionSpeed = abs(self.velocity.dx)
                    self.velocity.dx = -self.velocity.dx * 0.58
                    collided = true
                } else if x + half > self.dragBounds.maxX {
                    x = self.dragBounds.maxX - half
                    collisionSpeed = abs(self.velocity.dx)
                    self.velocity.dx = -self.velocity.dx * 0.58
                    collided = true
                }

                if y - half < self.dragBounds.minY {
                    y = self.dragBounds.minY + half
                    collisionSpeed = max(
                        collisionSpeed,
                        abs(self.velocity.dy)
                    )
                    self.velocity.dy = -self.velocity.dy * 0.58
                    collided = true
                } else if y + half > self.dragBounds.maxY {
                    y = self.dragBounds.maxY - half
                    collisionSpeed = max(
                        collisionSpeed,
                        abs(self.velocity.dy)
                    )
                    self.velocity.dy = -self.velocity.dy * 0.58
                    collided = true
                }

                self.position = CGPoint(x: x, y: y)

                if collided {
                    self.checkAndTriggerCollision(speed: collisionSpeed)
                }

                self.velocity.dx *= friction
                self.velocity.dy *= friction

                if hypot(self.velocity.dx, self.velocity.dy) < minimumSpeed {
                    self.physicsTimer?.invalidate()
                    self.physicsTimer = nil
                    self.currentPriority = self.chatbotIsThinking ? 75 : 0
                    self.softSettle()
                }
            }
        }
    }

    // MARK: - Collision Reactions

    private func checkAndTriggerCollision(speed: CGFloat) {
        guard Date().timeIntervalSince(lastCollisionTime) > 0.7 else {
            return
        }

        if speed > 700 {
            lastCollisionTime = Date()
            triggerPainedCollision()
        } else if speed > 280 {
            lastCollisionTime = Date()
            triggerSurprisedBounce()
        }
    }

    private func triggerPainedCollision() {
        invalidateScheduledRestore()

        currentPriority = 100
        isRecovering = true
        expression = .pained

        if !reduceMotion {
            withAnimation(
                .spring(response: 0.18, dampingFraction: 0.4)
            ) {
                squashX = 1.25
                squashY = 0.78
                rotation = Double.random(in: -9...9)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard self.isRecovering else { return }

                withAnimation(
                    .linear(duration: 0.06)
                        .repeatCount(4, autoreverses: true)
                ) {
                    self.offsetX = 7
                }
            }
        }

        let generation = actionGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            guard self.actionGeneration == generation else { return }

            self.expression = .recovering

            withAnimation(
                .spring(response: 0.35, dampingFraction: 0.7)
            ) {
                self.offsetX = 0
                self.squashX = 1
                self.squashY = 1
                self.rotation = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            guard self.actionGeneration == generation else { return }

            self.isRecovering = false
            self.currentPriority = self.chatbotIsThinking ? 75 : 0
            self.softSettle()
        }
    }

    private func triggerSurprisedBounce() {
        guard currentPriority <= 85 else { return }

        invalidateScheduledRestore()

        currentPriority = 85
        expression = .surprised

        if !reduceMotion {
            withAnimation(
                .spring(response: 0.25, dampingFraction: 0.5)
            ) {
                squashX = 1.12
                squashY = 0.88
            }
        }

        scheduleRestore(after: 0.45)
    }

    // MARK: - Tap Reactions

    public func onTap() {
        guard !isDragging else { return }

        let now = Date()
        guard now.timeIntervalSince(lastTapTime) > 0.35 else {
            return
        }

        lastTapTime = now

        // A tap should be able to interrupt thinking or speaking.
        invalidateScheduledRestore()

        currentPriority = 90
        tapReactionIndex = (tapReactionIndex + 1) % 7

        switch tapReactionIndex {
        case 0:
            expression = .surprised

            if !reduceMotion {
                withAnimation(
                    .spring(response: 0.22, dampingFraction: 0.5)
                ) {
                    offsetY = -18
                    squashX = 0.94
                    squashY = 1.08
                }
            }

            scheduleRestore(after: 0.65)

        case 1:
            expression = .angry

            if !reduceMotion {
                withAnimation(
                    .linear(duration: 0.06)
                        .repeatCount(4, autoreverses: true)
                ) {
                    offsetX = 6
                    rotation = 6
                }
            }

            scheduleRestore(after: 0.7)

        case 2:
            expression = .excited

            if !reduceMotion {
                withAnimation(
                    .spring(response: 0.45, dampingFraction: 0.65)
                ) {
                    rotation += 360
                    offsetY = -12
                }
            }

            scheduleRestore(after: 0.85)

        case 3:
            expression = .happy

            if !reduceMotion {
                withAnimation(
                    .spring(response: 0.2, dampingFraction: 0.55)
                ) {
                    offsetY = -16
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    guard self.currentPriority == 90 else { return }

                    withAnimation(
                        .spring(response: 0.2, dampingFraction: 0.55)
                    ) {
                        self.offsetY = -20
                    }
                }
            }

            scheduleRestore(after: 0.75)

        case 4:
            expression = .confused

            if !reduceMotion {
                withAnimation(
                    .spring(response: 0.3, dampingFraction: 0.65)
                ) {
                    rotation = 14
                    lookOffset = CGSize(width: -4, height: -2)
                }
            }

            scheduleRestore(after: 0.7)

        case 5:
            expression = .celebrating

            if !reduceMotion {
                withAnimation(
                    .spring(response: 0.28, dampingFraction: 0.5)
                ) {
                    squashX = 1.15
                    squashY = 0.85
                    offsetY = -14
                }
            }

            scheduleRestore(after: 0.75)

        default:
            expression = .happy

            if !reduceMotion {
                withAnimation(
                    .spring(response: 0.25, dampingFraction: 0.6)
                ) {
                    offsetX = 8
                    rotation = -8
                }
            }

            scheduleRestore(after: 0.7)
        }
    }

    // MARK: - Conversation Reactions

    public func onUserSentMessage() {
        chatbotIsThinking = false

        guard currentPriority < 90 else { return }

        invalidateScheduledRestore()

        currentPriority = 70
        expression = .listening

        if !reduceMotion {
            withAnimation(
                .spring(response: 0.25, dampingFraction: 0.7)
            ) {
                rotation = -4
                offsetY = -6
            }
        }

        scheduleRestore(after: 0.8)
    }

    public func onChatbotThinking(isThinking: Bool) {
        chatbotIsThinking = isThinking

        if isThinking {
            guard currentPriority < 90 else { return }

            invalidateScheduledRestore()

            currentPriority = 75
            expression = .thinking
            lookOffset = CGSize(width: 4, height: -4)

            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.3)) {
                    rotation = 6
                }
            }
        } else {
            guard currentPriority < 90 else { return }

            if expression == .thinking {
                invalidateScheduledRestore()

                currentPriority = 65
                expression = .speaking

                if !reduceMotion {
                    withAnimation(
                        .spring(response: 0.25, dampingFraction: 0.7)
                    ) {
                        rotation = 0
                        lookOffset = .zero
                    }
                }

                scheduleRestore(after: 0.9)
            }
        }
    }

    public func onRidePlanCompleted() {
        guard currentPriority < 90 else { return }

        invalidateScheduledRestore()

        currentPriority = 85
        expression = .celebrating

        if !reduceMotion {
            withAnimation(
                .spring(response: 0.3, dampingFraction: 0.5)
            ) {
                offsetY = -24
                rotation = 8
            }
        }

        scheduleRestore(after: 1.2)
    }

    public func onChatbotError() {
        guard currentPriority < 90 else { return }

        invalidateScheduledRestore()

        currentPriority = 65
        expression = .confused

        if !reduceMotion {
            withAnimation(
                .spring(response: 0.25, dampingFraction: 0.6)
            ) {
                rotation = -8
            }
        }

        scheduleRestore(after: 1.0)
    }

    // MARK: - Message-Based Reactions

    public func onMessageReceived(_ text: String) {
        guard currentPriority < 90 else { return }

        let lower = text.lowercased()

        if matchesAny(lower, [
            "congratulations", "awesome", "perfect",
            "ride created", "all set", "let's go",
            "great news", "successfully", "booked", "confirmed"
        ]) {
            triggerContextReaction(
                .happy,
                priority: 65,
                duration: 1.0,
                jump: -10,
                tilt: 5
            )
            return
        }

        if matchesAny(lower, [
            "amazing", "incredible", "beautiful route",
            "scenic", "waterfall", "epic",
            "breathtaking", "stunning"
        ]) {
            triggerContextReaction(
                .excited,
                priority: 65,
                duration: 0.9,
                jump: -14,
                tilt: 4
            )
            return
        }

        if matchesAny(lower, [
            "sorry", "couldn't", "error", "failed",
            "unable", "not found", "issue",
            "problem", "unfortunately"
        ]) {
            triggerContextReaction(
                .confused,
                priority: 65,
                duration: 0.9,
                jump: 0,
                tilt: -8
            )
            return
        }

        if matchesAny(lower, [
            "which", "where would", "do you want",
            "would you like", "can you tell",
            "what time", "how many", "could you"
        ]) {
            triggerContextReaction(
                .listening,
                priority: 65,
                duration: 0.8,
                jump: -4,
                tilt: -4
            )
            return
        }

        if matchesAny(lower, [
            "let me check", "searching", "looking up",
            "finding", "calculating", "one moment"
        ]) {
            triggerContextReaction(
                .thinking,
                priority: 65,
                duration: 0.7,
                jump: 0,
                tilt: 6
            )
            return
        }

        if matchesAny(lower, [
            "hey", "hello", "hi there", "good morning",
            "good evening", "welcome back", "nice to see"
        ]) {
            triggerContextReaction(
                .happy,
                priority: 65,
                duration: 0.8,
                jump: -8,
                tilt: 3
            )
            return
        }

        if matchesAny(lower, [
            "ride safe", "see you", "goodbye",
            "take care", "safe travels"
        ]) {
            triggerContextReaction(
                .happy,
                priority: 65,
                duration: 1.0,
                jump: -6,
                tilt: 0
            )
        }
    }

    private func matchesAny(
        _ text: String,
        _ keywords: [String]
    ) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private func triggerContextReaction(
        _ expression: EllisExpression,
        priority: Int,
        duration: Double,
        jump: CGFloat,
        tilt: Double
    ) {
        guard currentPriority < 90 else { return }

        invalidateScheduledRestore()

        currentPriority = priority
        self.expression = expression

        if !reduceMotion {
            withAnimation(
                .spring(response: 0.25, dampingFraction: 0.65)
            ) {
                if jump != 0 {
                    offsetY = jump
                }

                if tilt != 0 {
                    rotation = tilt
                }
            }
        }

        scheduleRestore(after: duration)
    }

    // MARK: - Idle Behaviour

    private func startIdleScheduler() {
        scheduleNextIdleAction()
    }

    private func scheduleNextIdleAction() {
        idleTimer?.invalidate()

        let delay = Double.random(in: 3.2...6.8)

        idleTimer = Timer.scheduledTimer(
            withTimeInterval: delay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                self.performRandomIdleAction()
                self.scheduleNextIdleAction()
            }
        }
    }

    private func performRandomIdleAction() {
        guard !isDragging,
              !isRecovering,
              currentPriority < 60
        else {
            return
        }

        if chatbotIsThinking {
            switch Int.random(in: 0...3) {
            case 0:
                glance(
                    offset: CGSize(width: -4, height: 0),
                    expression: .lookLeft
                )

            case 1:
                glance(
                    offset: CGSize(width: 4, height: 0),
                    expression: .lookRight
                )

            case 2:
                glance(
                    offset: CGSize(width: 0, height: -4),
                    expression: .lookUp
                )

            default:
                performBlink()
            }

            return
        }

        switch Int.random(in: 0...10) {
        case 0, 1, 2, 3:
            performBlink()

        case 4:
            performDoubleBlink()

        case 5:
            glance(
                offset: CGSize(width: -6, height: 0),
                expression: .lookLeft
            )

        case 6:
            glance(
                offset: CGSize(width: 6, height: 0),
                expression: .lookRight
            )

        case 7:
            glance(
                offset: CGSize(width: 0, height: -5),
                expression: .lookUp
            )

        case 8:
            tiltHead()

        case 9:
            if !reduceMotion {
                withAnimation(
                    .spring(response: 0.25, dampingFraction: 0.6)
                ) {
                    offsetY = -10
                }

                let generation = actionGeneration

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard self.actionGeneration == generation else {
                        return
                    }

                    self.softSettle()
                }
            }

        default:
            performBlink()
        }
    }

    // MARK: - Natural Blinking

    private func startBlinkScheduler() {
        scheduleNextBlink()
    }

    private func scheduleNextBlink() {
        blinkTimer?.invalidate()

        let delay = Double.random(in: 2.5...7.0)

        blinkTimer = Timer.scheduledTimer(
            withTimeInterval: delay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if !self.isDragging && self.currentPriority < 80 {
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

    private func performBlink() {
        withAnimation(.easeInOut(duration: 0.10)) {
            blinkProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeInOut(duration: 0.10)) {
                self.blinkProgress = 0
            }
        }
    }

    private func performDoubleBlink() {
        performBlink()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            self.performBlink()
        }
    }

    // MARK: - Eye Movement

    private func glance(
        offset: CGSize,
        expression: EllisExpression
    ) {
        let generation = actionGeneration

        self.expression = expression

        withAnimation(.easeInOut(duration: 0.2)) {
            lookOffset = offset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            guard self.actionGeneration == generation,
                  !self.isDragging
            else {
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                self.lookOffset = .zero
                self.expression = self.chatbotIsThinking
                    ? .thinking
                    : .idle
            }
        }
    }

    // MARK: - Head Tilt

    private func tiltHead() {
        let generation = actionGeneration
        let angle = Bool.random() ? 9.0 : -9.0

        withAnimation(
            .spring(response: 0.35, dampingFraction: 0.7)
        ) {
            rotation = angle
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard self.actionGeneration == generation else { return }

            withAnimation(
                .spring(response: 0.35, dampingFraction: 0.7)
            ) {
                self.rotation = 0
            }
        }
    }

    // MARK: - Floating Animation

    private func startFloatingLoop() {
        floatTimer?.invalidate()

        floatTimer = Timer.scheduledTimer(
            withTimeInterval: 0.033,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isDragging,
                      !self.isRecovering,
                      self.currentPriority < 60,
                      self.expression == .idle ||
                      self.expression == .thinking ||
                      self.expression == .speaking
                else {
                    return
                }

                self.floatPhase += 0.045

                let amount: CGFloat = self.reduceMotion ? 0.5 : 2.5

                self.offsetY = sin(self.floatPhase) * amount
            }
        }
    }

    // MARK: - Restore and Settle

    public func softSettle() {
        guard !isDragging else { return }

        withAnimation(
            .spring(response: 0.38, dampingFraction: 0.75)
        ) {
            rotation = chatbotIsThinking ? 6 : 0
            squashX = 1
            squashY = 1
            offsetX = 0
            offsetY = 0
            lookOffset = chatbotIsThinking
                ? CGSize(width: 4, height: -4)
                : .zero
            blinkProgress = 0
        }

        expression = chatbotIsThinking ? .thinking : .idle
        currentPriority = chatbotIsThinking ? 75 : 0
    }

    // MARK: - Reset Position

    public func resetToDefaultPosition() {
        physicsTimer?.invalidate()
        physicsTimer = nil

        velocity = .zero
        invalidateScheduledRestore()

        withAnimation(
            .spring(response: 0.45, dampingFraction: 0.75)
        ) {
            position = defaultPosition
            rotation = 0
            squashX = 1
            squashY = 1
            offsetX = 0
            offsetY = 0
        }

        softSettle()
    }
}
