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
        .containerBackground(.black, for: .navigation)
    }

    private func advance() { withAnimation(.easeInOut(duration: 0.2)) { step = step.next } }
}

// MARK: - Shared pieces

/// Small round pill-style action ("Stop here", "Skip", …).
private struct ActionButton: View {
    let title: String
    var prominent = false
    var compact = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.225)
                .foregroundStyle(prominent ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 30 : 36)
                .background(prominent ? Color.white : W.button, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// "CONVOY · now" header row. `leading` is the app icon or the sender avatar.
private struct AlertHeader<Leading: View>: View {
    @ViewBuilder var leading: Leading
    var body: some View {
        HStack(spacing: 7) {
            leading
            Text("CONVOY").font(.system(size: 11, weight: .semibold)).tracking(0.22).foregroundStyle(W.secondary)
            Spacer(minLength: 0)
            Text("now").font(.system(size: 11)).foregroundStyle(W.secondary)
        }
    }
}

private struct RouteBadgeIcon: View {
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(W.red, in: Circle())
    }
}

/// Avatar with the little red Convoy badge at its corner.
private struct SenderAvatar: View {
    let image: String
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(image).resizable().scaledToFill().frame(width: 22, height: 22).clipShape(Circle())
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 5, weight: .bold)).foregroundStyle(.white)
                .frame(width: 10, height: 10).background(W.red, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black, lineWidth: 1.5))
                .offset(x: 2, y: 2)
        }.frame(width: 22, height: 22)
    }
}

private struct AlertText: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 16, weight: .semibold)).tracking(-0.24).foregroundStyle(.white)
            if let detail { Text(detail).font(.system(size: 14)).tracking(-0.21).foregroundStyle(W.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 8)
    }
}

/// Header + text + spacer + actions — the common layout for W02–W07.
private struct AlertScreen<Leading: View, Extra: View, Actions: View>: View {
    @ViewBuilder var leading: Leading
    let title: String
    var detail: String? = nil
    @ViewBuilder var extra: Extra
    @ViewBuilder var actions: Actions
    var body: some View {
        VStack(spacing: 0) {
            AlertHeader { leading }
            AlertText(title: title, detail: detail)
            extra
            Spacer(minLength: 6)
            VStack(spacing: 6) { actions }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - W01 · Short look (wrist raise)

struct ShortLook: View {
    var onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 72, height: 72).background(W.red, in: Circle())
                    Image(systemName: "fuelpump.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                        .frame(width: 26, height: 26).background(W.amber, in: Circle())
                        .overlay(Circle().strokeBorder(.black, lineWidth: 3))
                }
                Color.clear.frame(height: 6)
                Text("Fuel stop in 2.1 km").font(.system(size: 16, weight: .semibold)).tracking(-0.24).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("CONVOY").font(.system(size: 11, weight: .semibold)).tracking(0.22).foregroundStyle(W.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - W02 · Long look

struct LongLook: View {
    var next: () -> Void
    var body: some View {
        AlertScreen(leading: { RouteBadgeIcon() }, title: "Fuel stop in 2.1 km",
                    detail: "HP Petrol Bunk on your left. All 6 riders were told.", extra: { EmptyView() }) {
            ActionButton(title: "Stop here", action: next)
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
        AlertScreen(leading: { RouteBadgeIcon() }, title: "You’re 800 m behind",
                    detail: "Let the crew know.", extra: { EmptyView() }) {
            ActionButton(title: "Wait for me", compact: true, action: next)
            ActionButton(title: "Taking a break", compact: true, action: next)
            ActionButton(title: "Go ahead", compact: true, action: next)
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
                Image(systemName: "fuelpump.fill").font(.system(size: 12)).foregroundStyle(.black)
                    .frame(width: 24, height: 24).background(W.amber, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text("HP Petrol Bunk").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text("1.2 km ahead · +2 min").font(.system(size: 11)).foregroundStyle(W.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(maxWidth: .infinity).frame(height: 43)
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
        AlertScreen(leading: { RouteBadgeIcon() }, title: "You’ve arrived",
                    detail: "Nandi Hills summit\n62.4 km · 1h 41m", extra: { EmptyView() }) {
            ActionButton(title: "Finish ride", action: next)
        }
    }
}

// MARK: - W08 · Summit reached

struct Summit: View {
    var done: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "mountain.2")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color(red: 0.23, green: 0.14, blue: 0))
                .frame(width: 44, height: 44)
                .background(LinearGradient(colors: [Color(red: 1, green: 0.82, blue: 0.48), Color(red: 0.95, green: 0.6, blue: 0.18)], startPoint: .top, endPoint: .bottom), in: Circle())
            Text("Summit reached").font(.system(size: 18, weight: .semibold)).tracking(-0.27).foregroundStyle(.white).padding(.top, 10)
            Text("Nandi Hills · 7:41 AM").font(.system(size: 12)).tracking(-0.18).foregroundStyle(W.secondary)
            HStack(spacing: 5) {
                stat("62.4", "km"); stat("1h 41m", "riding"); stat("6/6", "riders")
            }.padding(.top, 10)
            Spacer(minLength: 6)
            ActionButton(title: "Done", prominent: true, action: done)
        }
        .padding(.horizontal, 2)
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 0) {
            Text(v).font(.system(size: 14, weight: .semibold)).tracking(-0.21).foregroundStyle(.white).minimumScaleFactor(0.7).lineLimit(1)
            Text(l).font(.system(size: 10)).tracking(-0.15).foregroundStyle(W.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6).background(W.button, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview("Flow") { ContentView() }
#Preview("W01 · Short look") { ShortLook {} }
#Preview("W02 · Long look") { LongLook {} }
#Preview("W03 · Falling behind") { FallingBehind {} }
#Preview("W04 · Meera's watch") { MeerasWatch {} }
#Preview("W05 · Meera replied") { MeeraReplied {} }
#Preview("W06 · Stop added") { StopAdded {} }
#Preview("W07 · Arrived") { Arrived {} }
#Preview("W08 · Summit") { Summit {} }
