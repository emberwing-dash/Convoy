
import SwiftUI
import UIKit

// Interactive circular avatar cropper with pinch zoom and drag positioning.
struct ImageCropAdjustView: View {
    let originalImage: UIImage
    var onCrop: (UIImage, Data) -> Void
    var onCancel: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    @State private var viewportSize: CGSize = .zero

    private let cropDiameter: CGFloat = 260
    private let outputSize: CGFloat = 400

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { geo in
                    let containerSize = geo.size

                    ZStack {
                        Image(uiImage: originalImage)
                            .resizable()
                            .scaledToFill()
                            .frame(
                                width: containerSize.width,
                                height: containerSize.height
                            )
                            .scaleEffect(scale)
                            .offset(offset)
                            .frame(
                                width: containerSize.width,
                                height: containerSize.height
                            )
                            .clipped()
                            .contentShape(Rectangle())
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            let delta = value / lastScale
                                            lastScale = value
                                            scale = max(
                                                0.3,
                                                min(scale * delta, 4.0)
                                            )
                                        }
                                        .onEnded { _ in
                                            lastScale = 1.0
                                        },

                                    DragGesture()
                                        .onChanged { value in
                                            offset = CGSize(
                                                width: lastOffset.width
                                                    + value.translation.width,
                                                height: lastOffset.height
                                                    + value.translation.height
                                            )
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                )
                            )

                        CropMaskOverlay(diameter: cropDiameter)
                            .allowsHitTesting(false)
                    }
                    .onAppear {
                        viewportSize = containerSize
                    }
                    .onChange(of: containerSize) { _, newSize in
                        viewportSize = newSize
                    }
                }

                VStack {
                    Spacer()

                    VStack(spacing: 16) {
                        HStack(spacing: 14) {
                            Image(systemName: "minus.magnifyingglass")
                                .foregroundStyle(CV.cream.opacity(0.6))

                            Slider(value: $scale, in: 0.3...4.0)
                                .tint(CV.red)
                                .onChange(of: scale) { _, _ in
                                    lastScale = 1.0
                                }

                            Image(systemName: "plus.magnifyingglass")
                                .foregroundStyle(CV.cream.opacity(0.6))
                        }
                        .padding(.horizontal, 28)

                        HStack(spacing: 20) {
                            Button {
                                withAnimation(
                                    .spring(
                                        response: 0.35,
                                        dampingFraction: 0.8
                                    )
                                ) {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Reset")
                                }
                                .cvText(
                                    14,
                                    .semibold,
                                    color: CV.cream.opacity(0.8),
                                    inter: true
                                )
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                                .background(
                                    Color.white.opacity(0.1),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)

                            Text("Drag to reposition · Pinch to zoom")
                                .cvText(
                                    12,
                                    color: CV.cream.opacity(0.45),
                                    inter: true
                                )
                        }
                    }
                    .padding(.vertical, 20)
                    .background(
                        Color(hex: 0x1A1A1D, opacity: 0.95),
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 24,
                            topTrailingRadius: 24
                        )
                    )
                    .overlay {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 24,
                            topTrailingRadius: 24
                        )
                        .strokeBorder(
                            Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                    }
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationTitle("Adjust Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(CV.cream.opacity(0.8))
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard let (croppedImage, data) =
                                renderCroppedImage() else {
                            print("Failed to render cropped image")
                            return
                        }

                        onCrop(croppedImage, data)
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CV.red)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    /// Renders exactly the circular region visible through the crop guide.
    private func renderCroppedImage() -> (UIImage, Data)? {
        guard viewportSize.width > 0,
              viewportSize.height > 0 else {
            return nil
        }

        let targetSize = CGSize(
            width: outputSize,
            height: outputSize
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(
            size: targetSize,
            format: format
        )

        let croppedImage = renderer.image { context in
            let rect = CGRect(origin: .zero, size: targetSize)

            // Keep pixels outside the avatar circle transparent.
            context.cgContext.addEllipse(in: rect)
            context.cgContext.clip()

            let imageSize = originalImage.size

            // Match the preview's scaledToFill layout.
            let baseScale = max(
                viewportSize.width / imageSize.width,
                viewportSize.height / imageSize.height
            )

            let factor = outputSize / cropDiameter

            let drawWidth =
                imageSize.width * baseScale * scale * factor

            let drawHeight =
                imageSize.height * baseScale * scale * factor

            // The crop guide is centered in the preview.
            let drawX =
                (outputSize - drawWidth) / 2
                + offset.width * factor

            let drawY =
                (outputSize - drawHeight) / 2
                + offset.height * factor

            originalImage.draw(
                in: CGRect(
                    x: drawX,
                    y: drawY,
                    width: drawWidth,
                    height: drawHeight
                )
            )
        }

        guard let data = croppedImage.pngData() else {
            return nil
        }

        return (croppedImage, data)
    }
}

/// Circular crop guide with a dimmed exterior.
private struct CropMaskOverlay: View {
    let diameter: CGFloat

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.opacity(0.65)
                    .mask {
                        ZStack {
                            Rectangle()
                                .fill(Color.white)

                            Circle()
                                .frame(
                                    width: diameter,
                                    height: diameter
                                )
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }

                Circle()
                    .strokeBorder(CV.red, lineWidth: 2.5)
                    .frame(
                        width: diameter,
                        height: diameter
                    )
                    .shadow(
                        color: CV.red.opacity(0.4),
                        radius: 10
                    )

                Circle()
                    .strokeBorder(
                        Color.white.opacity(0.2),
                        lineWidth: 1
                    )
                    .frame(
                        width: diameter * 0.7,
                        height: diameter * 0.7
                    )
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }
}
