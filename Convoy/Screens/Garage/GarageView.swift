import SwiftUI

private let panel = Color(hex: 0x1C1C1F)
private let amber = Color(hex: 0xFFB020)

/// Shared "nav" for garage pages: back button + centered title (+ optional trailing view).
struct GarageNav<T: View>: View {
    @Environment(AppState.self) private var app
    let title: String
    @ViewBuilder var trailing: T
    var body: some View {
        ZStack {
            Text(title).cvText(17, .semibold, inter: true)
            HStack { CircleBackButton { app.pop() }; Spacer(); trailing }.padding(.horizontal, 20)
        }.padding(.top, 4).frame(maxHeight: .infinity, alignment: .top)
    }
}

/// G01 / G01b · Garage.
struct GarageView: View {
    @Environment(AppState.self) private var app
    private var ready: Bool { app.fillUps.count >= 2 }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    stage.padding(.top, 52)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ROYAL ENFIELD").cvText(11, .semibold, color: CV.red, tracking: 0.6, inter: true)
                            Text("Classic 350").cvText(30, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.6, inter: true)
                            Text("Signals edition · Marsh Grey · 2023").cvText(13, color: CV.muted, inter: true).padding(.top, 2)
                        }
                        Spacer()
                        Text("KA 01 RK 3500").cvText(13, .bold, color: Color(hex: 0x1A1A1D), inter: true)
                            .padding(.horizontal, 14).frame(height: 30).background(Color(hex: 0xF5D858), in: RoundedRectangle(cornerRadius: 8, style: .continuous)).padding(.top, 18)
                    }.padding(.horizontal, 24).padding(.top, 18)

                    HStack(spacing: 0) {
                        stat("18,420", "km on odo"); Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1, height: 40)
                        stat("349 cc", "engine"); Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1, height: 40)
                        stat("13 L", "fuel tank")
                    }
                    .frame(height: 84).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                    .padding(.horizontal, 20).padding(.top, 28)

                    sectionLabel("MILEAGE").padding(.top, 36)
                    mileageCard.padding(.horizontal, 20).padding(.top, 12)

                    sectionLabel("BIKE HEALTH").padding(.top, 34)
                    health.padding(.horizontal, 20).padding(.top, 12)

                    HStack {
                        sectionLabel("DOCUMENTS", inset: false); Spacer()
                        Text("1 expiring soon").cvText(12, .semibold, color: amber, inter: true)
                    }.padding(.horizontal, 24).padding(.top, 34)
                    docs.padding(.horizontal, 20).padding(.top, 12)

                    Button {} label: {
                        HStack(spacing: 8) { Image(systemName: "plus").font(.system(size: 12, weight: .bold)); Text("Add document").cvText(14, .semibold, inter: true) }
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    }.buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 14)

                    VStack(spacing: 0) {
                        linkRow("Specs", "Engine, power, weight"); Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.horizontal, 18)
                        linkRow("Service history", "3 services · last on 12 Jul")
                    }
                    .background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                    .padding(.horizontal, 20).padding(.top, 36).padding(.bottom, 50)
                }
            }.scrollIndicators(.hidden)
            GarageNav(title: "Garage") {
                Text("Edit").cvText(13, .semibold, inter: true).padding(.horizontal, 16).frame(height: 40).background(Color.white.opacity(0.12), in: Capsule())
            }
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private var stage: some View {
        ZStack {
            Ellipse().fill(RadialGradient(colors: [CV.red.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 150)).frame(width: 420, height: 300).offset(y: -50)
            Ellipse().fill(Color(hex: 0x0E0E10)).frame(width: 300, height: 56).offset(y: 100)
            Ellipse().strokeBorder(CV.red.opacity(0.35), lineWidth: 1).frame(width: 340, height: 64).offset(y: 98)
            Image("bike_classic").resizable().frame(width: 344, height: 215).offset(y: -20)
            HStack(spacing: 6) { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10)); Text("Drag to rotate 360°").cvText(11, .semibold, inter: true) }
                .padding(.horizontal, 12).frame(height: 28).background(Color.black.opacity(0.45), in: Capsule()).offset(y: 140)
            HStack(spacing: 6) {
                Capsule().fill(CV.cream).frame(width: 16, height: 6)
                ForEach(0..<3) { _ in Circle().fill(Color.white.opacity(0.25)).frame(width: 6, height: 6) }
            }.offset(y: 177)
        }.frame(height: 330)
    }

    private func sectionLabel(_ t: String, inset: Bool = true) -> some View {
        Text(t).cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true).padding(.leading, inset ? 24 : 0)
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 6) { Text(v).cvText(20, .bold, inter: true); Text(l).cvText(12, color: CV.cream.opacity(0.5), inter: true) }.frame(maxWidth: .infinity)
    }

    // MARK: mileage
    @ViewBuilder private var mileageCard: some View {
        if ready {
            Button { app.push(.mileageResults) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("36.2").cvText(40, .bold, tracking: -1, inter: true)
                        Text("km/l").cvText(16, .medium, color: CV.cream.opacity(0.55), inter: true)
                        Spacer()
                        Text("▲ 0.6").cvText(12, .semibold, color: CV.green, inter: true).padding(.horizontal, 10).frame(height: 26).background(CV.green.opacity(0.18), in: Capsule())
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.cream.opacity(0.6)).padding(.leading, 4)
                    }
                    Text("Approx · average of 5 fill-ups").cvText(13, color: CV.cream.opacity(0.55), inter: true).padding(.top, 2)
                    HStack(alignment: .bottom, spacing: 22) {
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(Array([22, 30, 38, 28, 40].enumerated()), id: \.offset) { i, h in
                                RoundedRectangle(cornerRadius: 3).fill(i == 4 ? CV.red : Color(hex: 0x3A3A3E)).frame(width: 10, height: CGFloat(h))
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) { Circle().fill(CV.red).frame(width: 5, height: 5); Text("Last tank").cvText(12, color: CV.cream.opacity(0.55), inter: true) }
                            Text("36.8 km/l").cvText(15, .bold, inter: true)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Best tank").cvText(12, color: CV.cream.opacity(0.55), inter: true)
                            Text("37.4 km/l").cvText(15, .bold, inter: true)
                        }
                    }.padding(.top, 18)
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.top, 16)
                    HStack(alignment: .top) {
                        mini("≈ 470 km", "full-tank range"); Spacer(); mini("₹2.84", "cost per km"); Spacer(); mini("9 Oct", "last fill-up")
                    }.padding(.top, 14)
                }
                .padding(18)
                .background(LinearGradient(colors: [CV.red.opacity(0.18), panel], startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }.buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button { app.push(app.fillUps.isEmpty ? .mileageIntro : .mileageProgress) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "fuelpump").font(.system(size: 18)).foregroundStyle(CV.red).frame(width: 40, height: 40).background(CV.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Find your real km/l").cvText(16, .bold, inter: true)
                            Text(app.fillUps.isEmpty ? "Not tracked yet" : "1 of 2 fill-ups logged").cvText(13, color: CV.cream.opacity(0.55), inter: true)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.cream.opacity(0.6))
                    }
                }.buttonStyle(.plain)
                HStack(spacing: 8) {
                    slot(1, app.fillUps.isEmpty ? "Not logged yet" : "Logged"); slot(2, "Not logged yet")
                }.padding(.top, 18)
                Text("Log 2 full-tank fill-ups to see your approx km/l.").cvText(13, color: CV.cream.opacity(0.55), inter: true).padding(.top, 14)
                PrimaryButton(title: app.fillUps.isEmpty ? "Log first fill-up" : "Log fill-up 2") { app.push(.logFillUp) }.padding(.top, 12)
            }
            .padding(18)
            .background(LinearGradient(colors: [CV.red.opacity(0.14), panel], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }
    private func slot(_ n: Int, _ sub: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").cvText(13, .semibold, color: CV.cream.opacity(0.6), inter: true).frame(width: 28, height: 28).background(Color.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Fill-up \(n)").cvText(14, .semibold, inter: true)
                Text(sub).cvText(11, color: CV.cream.opacity(0.5), inter: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity).frame(height: 52)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
    private func mini(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(v).cvText(15, .bold, inter: true); Text(l).cvText(11, color: CV.cream.opacity(0.5), inter: true) }
    }

    // MARK: health + docs
    private var health: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next service").cvText(17, .bold, inter: true)
                    Text("in 340 km · around 20 Oct").cvText(13, color: CV.cream.opacity(0.55), inter: true)
                }
                Spacer()
                Text("Book").cvText(13, .semibold, color: amber, inter: true).padding(.horizontal, 22).frame(height: 32).background(amber.opacity(0.2), in: Capsule())
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12)); Capsule().fill(amber).frame(width: g.size.width * 0.83)
                }
            }.frame(height: 6).padding(.top, 14)
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.top, 22)
            HStack(alignment: .top, spacing: 0) {
                hm("Tyres", "OK", CV.green); hm("Chain", "Lube soon", amber); hm("Battery", "OK", CV.green)
            }.padding(.top, 18)
        }
        .padding(18).background(panel, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }
    private func hm(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t).cvText(12, color: CV.cream.opacity(0.5), inter: true)
            HStack(spacing: 6) { Circle().fill(c).frame(width: 7, height: 7); Text(v).cvText(14, .semibold, inter: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var docs: some View {
        let items: [(String, String, Color)] = [("RC", "Valid till 2038", CV.green), ("Insurance", "Till Mar 2027", CV.green), ("PUC", "Expires in 18 days", amber), ("Licence", "Till 2041", CV.green)]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            ForEach(items, id: \.0) { n, sub, c in
                Button { app.push(.document(n)) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text").font(.system(size: 16)).foregroundStyle(CV.red).frame(width: 34, height: 40).background(CV.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(n).cvText(17, .bold, inter: true)
                            HStack(spacing: 5) { Circle().fill(c).frame(width: 6, height: 6); Text(sub).cvText(12, color: c == amber ? amber : CV.cream.opacity(0.55), inter: true) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).frame(height: 80).background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }
    private func linkRow(_ t: String, _ sub: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) { Text(t).cvText(16, .bold, inter: true); Text(sub).cvText(13, color: CV.cream.opacity(0.55), inter: true) }
            Spacer(); Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.cream.opacity(0.6))
        }.padding(.horizontal, 18).frame(height: 64)
    }
}

/// G02 · Document (Insurance layout, per the prototype every doc opens this screen).
struct DocumentView: View {
    @Environment(AppState.self) private var app
    let name: String
    @State private var reminder = true
    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            Text("IL").cvText(18, .bold, color: CV.ink, inter: true).frame(width: 44, height: 44).background(Color(hex: 0xF5EDDE), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ICICI Lombard").cvText(18, .bold, inter: true)
                                Text("Comprehensive · Two-wheeler").cvText(12, color: CV.cream.opacity(0.55), inter: true)
                            }
                            Spacer()
                            Text("● Active").cvText(12, .semibold, color: CV.green, inter: true).padding(.horizontal, 10).frame(height: 25).background(CV.green.opacity(0.18), in: Capsule())
                        }
                        Text("POLICY NUMBER").cvText(11, .semibold, color: CV.cream.opacity(0.5), tracking: 0.5, inter: true).padding(.top, 22)
                        HStack {
                            Text("3005 / 2918 / 4471 / 00").cvText(17, .bold, inter: true)
                            Spacer()
                            Text("Copy").cvText(13, .semibold, color: CV.cream.opacity(0.6), inter: true)
                        }.padding(.top, 4)
                        HStack { Text("15 Mar 2026").cvText(12, color: CV.cream.opacity(0.55), inter: true); Spacer(); Text("14 Mar 2027").cvText(12, color: CV.cream.opacity(0.55), inter: true) }.padding(.top, 18)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.15)); Capsule().fill(CV.cream).frame(width: g.size.width * 0.59)
                                Circle().fill(CV.cream).frame(width: 12, height: 12).offset(x: g.size.width * 0.59 - 6)
                            }
                        }.frame(height: 12).padding(.top, 6)
                        HStack { Text("151 days left").cvText(14, .semibold, inter: true); Spacer(); Text("Renews 14 Mar 2027").cvText(12, color: CV.cream.opacity(0.55), inter: true) }.padding(.top, 8)
                    }
                    .padding(18).background(LinearGradient(colors: [CV.red.opacity(0.18), Color(hex: 0x1C1C1F)], startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1)).padding(.top, 62)

                    Text("WHAT’S COVERED").cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.5, inter: true).padding(.top, 20).padding(.leading, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) { chip("Own damage"); chip("Third party") }
                        HStack(spacing: 8) { chip("Zero depreciation"); chip("Roadside assist") }
                    }.padding(.top, 8)

                    VStack(spacing: 0) {
                        detail("Vehicle", "Classic 350 · KA 01 RK 3500"); line
                        detail("IDV (insured value)", "₹1,62,000"); line
                        detail("Premium paid", "₹2,214 · 15 Mar 2026"); line
                        HStack {
                            Text("Roadside help").cvText(14, color: CV.cream.opacity(0.55), inter: true); Spacer()
                            Text("1800 2666").cvText(14, .semibold, inter: true)
                            Text("Call").cvText(13, .semibold, color: CV.red, inter: true).padding(.horizontal, 14).frame(height: 28).background(CV.red.opacity(0.18), in: Capsule()).padding(.leading, 6)
                        }.padding(.horizontal, 18).frame(height: 44)
                    }
                    .padding(.vertical, 4).background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).padding(.top, 14)

                    HStack(spacing: 12) {
                        Image(systemName: "bell").font(.system(size: 16)).foregroundStyle(amber).frame(width: 40, height: 40).background(amber.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Renewal reminder").cvText(15, .semibold, inter: true)
                            Text("30 days before · 12 Feb 2027").cvText(12, color: CV.cream.opacity(0.55), inter: true)
                        }
                        Spacer()
                        Toggle("", isOn: $reminder).labelsHidden().tint(CV.green)
                    }
                    .padding(.horizontal, 16).frame(height: 68).background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).padding(.top, 14)
                }.padding(.horizontal, 20).padding(.bottom, 110)
            }.scrollIndicators(.hidden)
            GarageNav(title: name) { Color.clear.frame(width: 44) }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                ShareLink(item: "\(name) · Classic 350 · KA 01 RK 3500") {
                    Text("Share").cvText(15, .semibold, inter: true).frame(width: 120, height: 52).background(Color(hex: 0x1C1C1F), in: Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                }
                PrimaryButton(title: "View PDF").frame(height: 52)
            }.padding(.horizontal, 20).padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
    private var line: some View { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.horizontal, 18) }
    private func detail(_ k: String, _ v: String) -> some View {
        HStack { Text(k).cvText(14, color: CV.cream.opacity(0.55), inter: true); Spacer(); Text(v).cvText(14, .semibold, inter: true) }.padding(.horizontal, 18).frame(height: 44)
    }
    private func chip(_ t: String) -> some View {
        HStack(spacing: 6) { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(CV.green); Text(t).cvText(14, .medium, inter: true) }
            .padding(.horizontal, 14).frame(height: 34).background(Color.white.opacity(0.05), in: Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}
