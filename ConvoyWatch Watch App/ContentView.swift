//
//  ContentView.swift
//  ConvoyWatch Watch App
//
//  Ride alerts, ported from the Figma "convoyAPPLEWATCH" file (W01 → W08).
//

import SwiftUI

// MARK: - Tokens

private enum W {
    static let red = Color(red: 1, green: 0.231, blue: 0.188)          // #FF3B30
    static let amber = Color(red: 0.961, green: 0.659, blue: 0.2)      // #F5A833
    static let secondary = Color(red: 0.6, green: 0.6, blue: 0.62)     // #99999E
    static let button = Color(red: 0.141, green: 0.141, blue: 0.149)   // #242426
}

/// The eight screens of the flow. Every action advances to the next one; "Done" loops back to the start,
/// exactly like the Figma prototype links.
private enum Step: Int, CaseIterable {
    case shortLook, longLook, fallingBehind, meerasWatch, meeraReplied, stopAdded, arrived, summit
    var next: Step { Step(rawValue: (rawValue + 1) % Step.allCases.count) ?? .shortLook }
}

// MARK: - Root

struct ContentView: View {
    @State private var step: Step = .shortLook

    var body: some View {
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
    }

    private func advance() { withAnimation(.easeInOut(duration: 0.2)) { step = step.next } }
}

// MARK: - Canvas

/// Draws a screen on Figma's 187 × 223 watch canvas, scaled to the real display width and anchored to the true top-left
/// (the system clock sits in the top-right exactly where the design leaves room for it). This keeps the Figma
/// paddings relative to the rounded screen edge on every watch size, so nothing clips at the corners.
private struct WatchCanvas<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 187
            content
                .frame(width: 187, height: geo.size.height / scale, alignment: .top)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Shared pieces

/// Figma's custom route / fuel / mountain glyphs, tinted.
private struct Glyph: View {
    let name: String
    var width: CGFloat
    var color: Color = .white
    var body: some View {
        Image(name).renderingMode(.template).resizable().scaledToFit().frame(width: width).foregroundStyle(color)
    }
}

/// Pill action ("Stop here", "Skip", …). Dark by default; white / amber / red for the primary one, as in the design.
private enum ActionStyle {
    case dark, white, amber, red
    var fill: Color { switch self { case .dark: W.button; case .white: .white; case .amber: W.amber; case .red: W.red } }
    var text: Color { switch self { case .dark, .red: .white; case .white, .amber: .black } }
}

private struct ActionButton: View {
    let title: String
    var style: ActionStyle = .dark
    var height: CGFloat = 36
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.225)
                .foregroundStyle(style.text)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(style.fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// "CONVOY · now" row. `leading` is the red app icon or the sender avatar.
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

/// 22 pt red circle with the route glyph (W02, W04, W07).
private struct AppIcon: View {
    var body: some View {
        Glyph(name: "glyph_route", width: 11).frame(width: 22, height: 22).background(W.red, in: Circle())
    }
}

/// 22 pt avatar with the tiny red Convoy badge at its corner (W03, W05, W06).
private struct SenderAvatar: View {
    let image: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image).resizable().scaledToFill().frame(width: 22, height: 22).clipShape(Circle())
            Glyph(name: "glyph_route", width: 5).frame(width: 10, height: 10).background(W.red, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black, lineWidth: 1.5))
                .offset(x: 14, y: 13)
        }.frame(width: 22, height: 22)
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

/// Header + text + (extra) + flexible space + actions — the shared layout of W02–W07 (10 pt sides, 12 pt bottom).
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

struct ShortLook: View {
    var onTap: () -> Void
    var body: some View {
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

struct LongLook: View {
    var next: () -> Void
    var body: some View {
        AlertScreen(leading: { AppIcon() }, title: "Fuel stop in 2.1 km",
                    detail: "HP Petrol Bunk on your left. All 6 riders were told.", extra: { EmptyView() }) {
            ActionButton(title: "Stop here", style: .amber, action: next)
            ActionButton(title: "Skip", action: next)
        }
    }
}

// MARK: - W03 · Meera falling behind

struct FallingBehind: View {
    var next: () -> Void
    var body: some View {
        AlertScreen(leading: { SenderAvatar(image: "avatar_meera") }, title: "Meera is 800 m back",
                    detail: "We’ve asked if she’s okay.", extra: { EmptyView() }) {
            ActionButton(title: "Wait for her", action: next)
            ActionButton(title: "Keep going", action: next)
        }
    }
}

// MARK: - W04 · Meera's watch · quick replies

struct MeerasWatch: View {
    var next: () -> Void
    var body: some View {
        AlertScreen(leading: { AppIcon() }, title: "You’re 800 m behind",
                    detail: "Let the crew know.", extra: { EmptyView() }) {
            ActionButton(title: "Wait for me", style: .white, height: 30, action: next)
            ActionButton(title: "Taking a break", height: 30, action: next)
            ActionButton(title: "Go ahead", height: 30, action: next)
        }
    }
}

// MARK: - W05 · Meera replied

struct MeeraReplied: View {
    var next: () -> Void
    var body: some View {
        AlertScreen(leading: { SenderAvatar(image: "avatar_meera") }, title: "Meera",
                    detail: "“Taking a break, go ahead, I’ll catch up.”", extra: { EmptyView() }) {
            ActionButton(title: "OK", action: next)
        }
    }
}

// MARK: - W06 · Arjun's watch · stop added

struct StopAdded: View {
    var next: () -> Void
    var body: some View {
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

struct Arrived: View {
    var next: () -> Void
    var body: some View {
        AlertScreen(leading: { AppIcon() }, title: "You’ve arrived",
                    detail: "Nandi Hills summit\n62.4 km · 1h 41m", extra: { EmptyView() }) {
            ActionButton(title: "Finish ride", style: .red, action: next)
        }
    }
}

// MARK: - W08 · Summit reached

struct Summit: View {
    var done: () -> Void
    var body: some View {
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

// MARK: - Previews

#Preview("Flow") { ContentView() }
#Preview("W01 · Short look") { ShortLook {} }
#Preview("W02 · Long look") { LongLook {} }
#Preview("W03 · Falling behind") { FallingBehind {} }
#Preview("W04 · Meera's watch") { MeerasWatch {} }
#Preview("W05 · Meera replied") { MeeraReplied {} }
#Preview("W06 · Stop added") { StopAdded {} }
#Preview("W07 · Arrived") { Arrived {} }
#Preview("W08 · Summit") { Summit {} }
