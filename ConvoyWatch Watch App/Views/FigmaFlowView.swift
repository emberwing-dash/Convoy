//
//  FigmaFlowView.swift
//  ConvoyWatch Watch App
//
//  Preserves the Figma prototype flow screens (W01 → W08) from the original design.
//

import SwiftUI

public enum FigmaStep: Int, CaseIterable {
    case shortLook, longLook, fallingBehind, meerasWatch, meeraReplied, stopAdded, arrived, summit
    var next: FigmaStep { FigmaStep(rawValue: (rawValue + 1) % FigmaStep.allCases.count) ?? .shortLook }
}

public struct FigmaFlowView: View {
    @State private var step: FigmaStep = .shortLook
    @Environment(\.dismiss) private var dismiss
    
    public init(initialStep: FigmaStep = .shortLook) {
        self._step = State(initialValue: initialStep)
    }
    
    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch step {
                case .shortLook: ShortLook { advance() }
                case .longLook: LongLook { advance() }
                case .fallingBehind: FallingBehind { advance() }
                case .meerasWatch: MeerasWatch { advance() }
                case .meeraReplied: MeeraReplied { advance() }
                case .stopAdded: StopAdded { advance() }
                case .arrived: Arrived { advance() }
                case .summit: Summit { advance() }
                }
            }
            .id(step)
            .transition(.opacity)
            
            // Dismiss button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func advance() {
        withAnimation(.easeInOut(duration: 0.2)) {
            step = step.next
        }
    }
}

// MARK: - Shared Screen Template

private struct AlertHeader<Leading: View>: View {
    @ViewBuilder var leading: Leading
    var body: some View {
        HStack(spacing: 7) {
            leading
            Text("CONVOY").font(.system(size: 11, weight: .semibold)).tracking(0.22).foregroundStyle(W.secondary)
            Spacer(minLength: 0)
            Text("now").font(.system(size: 11)).tracking(-0.165).foregroundStyle(W.secondary)
        }
    }
}

private struct AlertText: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 16, weight: .semibold)).tracking(-0.24)
                .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
            if let detail {
                Text(detail).font(.system(size: 14)).tracking(-0.21).foregroundStyle(W.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 8)
    }
}

private struct AlertScreen<Leading: View, Extra: View, Actions: View>: View {
    @ViewBuilder var leading: Leading
    let title: String
    var detail: String? = nil
    @ViewBuilder var extra: Extra
    @ViewBuilder var actions: Actions
    var body: some View {
        WatchCanvas {
            VStack(spacing: 0) {
                AlertHeader { leading }
                AlertText(title: title, detail: detail)
                extra
                Spacer(minLength: 6)
                VStack(spacing: 6) { actions }
            }
            .padding(.horizontal, 10)
            .padding(.top, 28)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - W01 · Short look (wrist raise)

public struct ShortLook: View {
    public var onTap: () -> Void
    public init(onTap: @escaping () -> Void) { self.onTap = onTap }
    
    public var body: some View {
        WatchCanvas {
            Button(action: onTap) {
                VStack(spacing: 6) {
                    ZStack(alignment: .bottomTrailing) {
                        Glyph(name: "glyph_route", width: 36).frame(width: 72, height: 72).background(W.red, in: Circle())
                        Glyph(name: "glyph_fuel", width: 13).frame(width: 26, height: 26).background(W.amber, in: Circle())
                            .overlay(Circle().strokeBorder(.black, lineWidth: 3))
                            .offset(x: 4, y: 4)
                    }
                    .frame(width: 72, height: 72)
                    Color.clear.frame(width: 10, height: 6)
                    Text("Fuel stop in 2.1 km").font(.system(size: 16, weight: .semibold)).tracking(-0.24)
                        .foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
                    Text("CONVOY").font(.system(size: 11, weight: .semibold)).tracking(0.22).foregroundStyle(W.secondary)
                }
                .padding(.horizontal, 10).padding(.top, 24).padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - W02 · Long look

public struct LongLook: View {
    public var next: () -> Void
    public init(next: @escaping () -> Void) { self.next = next }
    
    public var body: some View {
        AlertScreen(leading: { AppIcon() }, title: "Fuel stop in 2.1 km",
                    detail: "HP Petrol Bunk on your left. All 6 riders were told.", extra: { EmptyView() }) {
            ActionButton(title: "Stop here", style: .amber, action: next)
            ActionButton(title: "Skip", action: next)
        }
    }
}

// MARK: - W03 · Meera falling behind

public struct FallingBehind: View {
    public var next: () -> Void
    public init(next: @escaping () -> Void) { self.next = next }
    
    public var body: some View {
        AlertScreen(leading: { SenderAvatar(image: "avatar_meera") }, title: "Meera is 800 m back",
                    detail: "We’ve asked if she’s okay.", extra: { EmptyView() }) {
            ActionButton(title: "Wait for her", action: next)
            ActionButton(title: "Keep going", action: next)
        }
    }
}

// MARK: - W04 · Meera's watch · quick replies

public struct MeerasWatch: View {
    public var next: () -> Void
    public init(next: @escaping () -> Void) { self.next = next }
    
    public var body: some View {
        AlertScreen(leading: { AppIcon() }, title: "You’re 800 m behind",
                    detail: "Let the crew know.", extra: { EmptyView() }) {
            ActionButton(title: "Wait for me", style: .white, height: 30, action: next)
            ActionButton(title: "Taking a break", height: 30, action: next)
            ActionButton(title: "Go ahead", height: 30, action: next)
        }
    }
}

// MARK: - W05 · Meera replied

public struct MeeraReplied: View {
    public var next: () -> Void
    public init(next: @escaping () -> Void) { self.next = next }
    
    public var body: some View {
        AlertScreen(leading: { SenderAvatar(image: "avatar_meera") }, title: "Meera",
                    detail: "“Taking a break, go ahead, I’ll catch up.”", extra: { EmptyView() }) {
            ActionButton(title: "OK", action: next)
        }
    }
}

// MARK: - W06 · Stop added

public struct StopAdded: View {
    public var next: () -> Void
    public init(next: @escaping () -> Void) { self.next = next }
    
    public var body: some View {
        AlertScreen(leading: { SenderAvatar(image: "avatar_rika") }, title: "Rika added a stop", extra: {
            HStack(spacing: 8) {
                Glyph(name: "glyph_fuel", width: 12).frame(width: 24, height: 24).background(W.amber, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text("HP Petrol Bunk").font(.system(size: 13, weight: .semibold)).tracking(-0.195).foregroundStyle(.white)
                    Text("1.2 km ahead · +2 min").font(.system(size: 11)).tracking(-0.165).foregroundStyle(W.secondary)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 7).frame(maxWidth: .infinity)
            .background(W.button, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 6)
        }) {
            ActionButton(title: "Got it", action: next)
        }
    }
}

// MARK: - W07 · Arrived

public struct Arrived: View {
    public var next: () -> Void
    public init(next: @escaping () -> Void) { self.next = next }
    
    public var body: some View {
        AlertScreen(leading: { AppIcon() }, title: "You’ve arrived",
                    detail: "Nandi Hills summit\n62.4 km · 1h 41m", extra: { EmptyView() }) {
            ActionButton(title: "Finish ride", style: .red, action: next)
        }
    }
}

// MARK: - W08 · Summit reached

public struct Summit: View {
    public var done: () -> Void
    public init(done: @escaping () -> Void) { self.done = done }
    
    public var body: some View {
        WatchCanvas {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(W.amber.opacity(0.22)).frame(width: 86, height: 86)
                    Circle().fill(W.amber).frame(width: 44, height: 44)
                    Glyph(name: "glyph_mountain", width: 20, color: .white)
                }
                .frame(width: 44, height: 44)
                Color.clear.frame(height: 10)
                Text("Summit reached").font(.system(size: 18, weight: .semibold)).tracking(-0.27).foregroundStyle(.white)
                Text("Nandi Hills · 7:41 AM").font(.system(size: 12)).tracking(-0.18).foregroundStyle(W.secondary)
                Color.clear.frame(height: 10)
                HStack(spacing: 5) {
                    stat("62.4", "km"); stat("1h 41m", "riding"); stat("6/6", "riders")
                }
                Spacer(minLength: 7)
                ActionButton(title: "Done", style: .white, action: done)
            }
            .padding(.horizontal, 10).padding(.top, 26).padding(.bottom, 12)
        }
    }
    
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 0) {
            Text(v).font(.system(size: 14, weight: .semibold)).tracking(-0.21).foregroundStyle(.white).minimumScaleFactor(0.7).lineLimit(1)
            Text(l).font(.system(size: 10)).tracking(-0.15).foregroundStyle(W.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6).background(W.button, in: RoundedRectangle(cornerRadius: 10))
    }
}
