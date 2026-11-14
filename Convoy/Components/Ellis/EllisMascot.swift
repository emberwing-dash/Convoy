import SwiftUI

// MARK: - Reusable Ellis Mascot SwiftUI Component
// Renders the authentic, untouched Ellis head image with expressive eye overlays,
// direct physics drag interactions, collision response, and whole-head animations.

public struct EllisMascot: View {
    @Bindable var controller: EllisController
    var size: CGFloat = 110.0
    /// Called when user finishes a drag more than 24pt from default position
    var onDraggedAway: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    public init(controller: EllisController, size: CGFloat = 110.0, onDraggedAway: (() -> Void)? = nil) {
        self.controller = controller
        self.size = size
        self.onDraggedAway = onDraggedAway
    }

    public var body: some View {
        mascotCore
            .frame(width: size, height: size)
            .position(controller.position)
            .gesture(dragGesture)
            .onAppear {
                controller.mascotSize = size
                controller.reduceMotion = systemReduceMotion
                controller.start()
            }
            .onDisappear {
                controller.stop()
            }
            .onChange(of: systemReduceMotion) { _, newValue in
                controller.reduceMotion = newValue
            }
    }

    // MARK: - Core Character Artwork + Overlays
    private var mascotCore: some View {
        ZStack {
            // Subtle ambient aura when celebrating or excited
            if controller.expression == .celebrating || controller.expression == .excited {
                Circle()
                    .fill(Color(hex: 0xFF6B00).opacity(0.35))
                    .frame(width: size * 1.15, height: size * 1.15)
                    .blur(radius: 16)
            }

            // Original untouched character head image
            Image("ellis_mascot")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)

            // Dynamic expressive eye overlay
            EllisEyeOverlay(
                expression: controller.expression,
                mascotSize: size,
                blinkProgress: controller.blinkProgress,
                lookOffset: controller.lookOffset
            )
            .frame(width: size, height: size)
        }
        // Whole-head animation transforms
        .rotationEffect(.degrees(controller.rotation))
        .scaleEffect(x: controller.squashX, y: controller.squashY)
        .offset(x: controller.offsetX, y: controller.offsetY)
        .shadow(
            color: Color.black.opacity(controller.isDragging ? 0.45 : 0.25),
            radius: controller.isDragging ? 18 : 8,
            y: controller.isDragging ? 12 : 4
        )
    }

    // MARK: - Drag & Tap Gesture
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let dist = hypot(value.translation.width, value.translation.height)
                if !controller.isDragging {
                    controller.onDragStarted(at: value.startLocation)
                    if dist >= 5.0 {
                        controller.onDragConfirmed()
                    }
                }
                if controller.isDragging {
                    controller.onDragChanged(translation: value.translation)
                }
            }
            .onEnded { value in
                let dist = hypot(value.translation.width, value.translation.height)
                if dist < 5.0 {
                    controller.isDragging = false
                    controller.currentPriority = 0
                    controller.onTap()
                } else {
                    controller.onDragEnded(finalTranslation: value.translation)
                    // Check if Ellis was dragged far from the default position
                    let def = controller.defaultPosition
                    let cur = controller.position
                    if hypot(cur.x - def.x, cur.y - def.y) > 24 {
                        onDraggedAway?()
                    }
                }
            }
    }
}
