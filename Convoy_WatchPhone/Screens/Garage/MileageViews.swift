import SwiftUI
import Charts

private let panel = Color(hex: 0x1C1C1F)

/// The "fill-up 1 → km ridden ÷ litres used = km/l" diagram shared by G03 / G05.
private struct MileageDiagram: View {
    var firstLogged: Bool
    var firstLabel: String
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                pump("Fill-up 1", firstLogged ? firstLabel : "Full tank", logged: firstLogged)
                ZStack {
                    Rectangle().fill(firstLogged ? CV.red : Color.white.opacity(0.25)).frame(height: 1.5)
                    Text(firstLogged ? "Riding now" : "You ride").cvText(11, .semibold, color: CV.cream.opacity(0.8), inter: true).padding(.horizontal, 10).frame(height: 24)
                        .background(Color(hex: 0x1F1F22), in: Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                }.frame(maxWidth: .infinity).padding(.bottom, 26)
                pump("Fill-up 2", "Full tank again", logged: false)
            }
            HStack(spacing: 10) {
                Text("km ridden").cvText(13, .medium, inter: true); Text("÷").cvText(13, color: CV.cream.opacity(0.5), inter: true)
                Text("litres used").cvText(13, .medium, inter: true); Text("=").cvText(13, color: CV.cream.opacity(0.5), inter: true)
                Text("km/l").cvText(13, .semibold, color: CV.red, inter: true)
            }.frame(maxWidth: .infinity).frame(height: 36).background(Color.white.opacity(0.06), in: Capsule())
        }
        .padding(16)
        .background(LinearGradient(colors: [CV.red.opacity(0.14), panel], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
    private func pump(_ t: String, _ sub: String, logged: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "fuelpump").font(.system(size: 22)).foregroundStyle(logged ? CV.red : CV.cream.opacity(0.5))
                    .frame(width: 64, height: 64).background(logged ? CV.red.opacity(0.2) : Color.white.opacity(0.03), in: Circle())
                    .overlay(Circle().strokeBorder(logged ? CV.red : Color.white.opacity(0.3), style: StrokeStyle(lineWidth: logged ? 1.5 : 1, dash: logged ? [] : [4, 3])))
                if logged { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22).background(CV.green, in: Circle()).offset(x: 6, y: -4) }
            }
            VStack(spacing: 2) {
                Text(t).cvText(14, .semibold, inter: true)
                Text(sub).cvText(11, color: logged ? CV.green : CV.cream.opacity(0.5), inter: true)
            }
        }.frame(width: 96)
    }
}

private struct StatusPill: View {
    let text: String; let on: Bool
    var body: some View {
        HStack(spacing: 6) { Circle().fill(on ? CV.red : CV.cream.opacity(0.4)).frame(width: 6, height: 6); Text(text).cvText(12, .semibold, color: CV.cream.opacity(0.7), inter: true) }
            .padding(.horizontal, 12).frame(height: 28).background(Color.white.opacity(0.08), in: Capsule())
    }
}

/// G03 · Mileage — get started.
struct MileageIntroView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MileageDiagram(firstLogged: false, firstLabel: "").padding(.top, 62)
                    StatusPill(text: "0 of 2 fill-ups logged", on: false).padding(.top, 14).padding(.leading, 4)
                    Text("Log 2 fill-ups\nto see your mileage").cvText(28, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.5, lineHeight: 34, inter: true).padding(.top, 14)
                    Text("One full tank starts the count, the next one measures the fuel you actually used.").cvText(15, color: CV.cream.opacity(0.55), lineHeight: 21, inter: true).padding(.top, 8)
                    VStack(spacing: 0) {
                        step(1, "Fill the tank to full", "Log it with the odometer reading.", on: true); Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 56)
                        step(2, "Ride like you always do", "City, highway, weekend runs. It all counts.", on: false); Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 56)
                        step(3, "Fill to full again, log it", "Your approx km/l shows up right away.", on: false)
                    }
                    .background(panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).padding(.top, 24)
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
            GarageNav(title: "Mileage") { Color.clear.frame(width: 44) }
        }
        .safeAreaInset(edge: .bottom) { PrimaryButton(title: "Log first fill-up") { app.push(.logFillUp) }.padding(.horizontal, 20).padding(.bottom, 8) }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
    private func step(_ n: Int, _ t: String, _ s: String, on: Bool) -> some View {
        HStack(spacing: 14) {
            Text("\(n)").cvText(13, .bold, color: on ? CV.ink : CV.cream.opacity(0.7), inter: true).frame(width: 32, height: 32).background(on ? Color(hex: 0xF5EDDE) : Color.white.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) { Text(t).cvText(15, .semibold, inter: true); Text(s).cvText(13, color: CV.cream.opacity(0.55), inter: true) }
            Spacer(minLength: 0)
        }.padding(.horizontal, 16).frame(height: 62)
    }
}

/// G04 / G04b · Log fill-up (1 of 2, then 2 of 2).
struct LogFillUpView: View {
    @Environment(AppState.self) private var app
    @State private var odo = ""
    @State private var litres = ""
    @State private var price = "102.90"
    @State private var fullTank = true
    @FocusState private var focus: Field?
    enum Field { case odo, litres, price }

    private var second: Bool { app.fillUps.count == 1 }
    private var odoValue: Int { Int(odo.filter(\.isNumber)) ?? 0 }
    private var litresValue: Double { Double(litres) ?? 0 }
    private var priceValue: Double { Double(price) ?? 0 }
    private var total: Int { Int((litresValue * priceValue).rounded()) }
    private var valid: Bool { odoValue > (app.fillUps.last?.odo ?? 0) && litresValue > 0 && priceValue > 0 }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) { Circle().fill(CV.red).frame(width: 6, height: 6); Text("Fill-up \(second ? 2 : 1) of 2 · full tank").cvText(12, .semibold, inter: true) }
                        .padding(.horizontal, 12).frame(height: 25).background(Color.white.opacity(0.1), in: Capsule()).padding(.top, 62)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            Text("ODOMETER").cvText(11, .semibold, color: CV.cream.opacity(0.55), tracking: 0.5, inter: true)
                            Spacer()
                            Image(systemName: "gauge.medium").font(.system(size: 16)).foregroundStyle(CV.cream.opacity(0.7)).frame(width: 38, height: 38).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            TextField("", text: $odo, prompt: Text(second ? "18,420" : "18,058").foregroundColor(CV.cream.opacity(0.25))).keyboardType(.numberPad).focused($focus, equals: .odo).tint(CV.red)
                                .cvText(48, .bold, tracking: -1, inter: true).fixedSize()
                            Text("km").cvText(17, .medium, color: CV.cream.opacity(0.55), inter: true)
                        }.padding(.top, 2)
                        Group {
                            if second, let first = app.fillUps.first, odoValue > first.odo {
                                Text("\(odoValue - first.odo) km since fill-up 1 (\(first.odo.formatted()) km)").foregroundStyle(CV.green)
                            } else { Text("Read it off your dash at the pump").foregroundStyle(CV.cream.opacity(0.55)) }
                        }.cvText(12, inter: true).padding(.top, 8)
                    }
                    .padding(18).background(panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(CV.red.opacity(focus == .odo || focus == nil ? 0.8 : 0.2), lineWidth: 1.5)).padding(.top, 14)

                    HStack(spacing: 12) {
                        field("FUEL ADDED", $litres, "litres", prompt: second ? "10.0" : "12.4", f: .litres, keyboard: .decimalPad)
                        field("PRICE / LITRE", $price, nil, prefix: "₹", prompt: "102.90", f: .price, keyboard: .decimalPad)
                    }.padding(.top, 14)
                    HStack { Text("Total paid").cvText(14, color: CV.cream.opacity(0.55), inter: true); Spacer(); Text("₹\(total.formatted())").cvText(15, .bold, inter: true) }
                        .padding(.horizontal, 18).frame(height: 48).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous)).padding(.top, 14)
                    HStack(spacing: 12) {
                        Image(systemName: "fuelpump").foregroundStyle(CV.red).frame(width: 40, height: 40).background(CV.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) { Text("Filled to full tank").cvText(15, .semibold, inter: true); Text("Needed for an accurate km/l").cvText(12, color: CV.cream.opacity(0.55), inter: true) }
                        Spacer(); Toggle("", isOn: $fullTank).labelsHidden().tint(CV.green)
                    }.padding(.horizontal, 16).frame(height: 72).background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).padding(.top, 14)
                    VStack(spacing: 0) {
                        detail("calendar", "Date", "Today, 9:41 AM"); Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 48)
                        detail("location", "Fuel station", "Add (optional)", dim: true)
                    }.background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).padding(.top, 14)
                    Text(second ? "Save to see your km/l: about \(kmpl) on this tank." : "Next: fill to full again and log it to see your km/l.")
                        .cvText(12, color: CV.cream.opacity(0.5), inter: true).frame(maxWidth: .infinity).padding(.top, 28)
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }.scrollDismissesKeyboard(.interactively).scrollIndicators(.hidden)
            GarageNav(title: "Log fill-up") { Color.clear.frame(width: 44) }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Save fill-up") { save() }.opacity(valid ? 1 : 0.4).padding(.horizontal, 20).padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear { focus = .odo }
    }

    private var kmpl: String {
        guard let first = app.fillUps.first, litresValue > 0 else { return "—" }
        return String(format: "%.1f", Double(odoValue - first.odo) / litresValue)
    }
    private func save() {
        guard valid else { return }
        app.fillUps.append(FillUp(odo: odoValue, litres: litresValue, price: priceValue))
        focus = nil
        if app.fillUps.count >= 2 { app.path.removeLast(); app.push(.mileageResults) } else { app.path.removeLast(); app.push(.mileageProgress) }
    }
    private func field(_ t: String, _ b: Binding<String>, _ unit: String?, prefix: String? = nil, prompt: String, f: Field, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t).cvText(11, .semibold, color: CV.cream.opacity(0.55), tracking: 0.5, inter: true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let p = prefix { Text(p).cvText(24, .bold, inter: true) }
                TextField("", text: b, prompt: Text(prompt).foregroundColor(CV.cream.opacity(0.25))).keyboardType(keyboard).focused($focus, equals: f).tint(CV.red).cvText(24, .bold, inter: true).fixedSize()
                if let u = unit { Text(u).cvText(14, color: CV.cream.opacity(0.55), inter: true) }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).frame(height: 84)
        .background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(focus == f ? CV.red.opacity(0.8) : Color.white.opacity(0.07), lineWidth: 1))
    }
    private func detail(_ icon: String, _ t: String, _ v: String, dim: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(CV.cream.opacity(0.6)).frame(width: 20)
            Text(t).cvText(15, .semibold, inter: true); Spacer()
            Text(v).cvText(14, color: dim ? CV.cream.opacity(0.4) : CV.cream.opacity(0.7), inter: true)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.cream.opacity(0.5))
        }.padding(.horizontal, 16).frame(height: 58)
    }
}

/// G05 · Mileage — 1 of 2 logged.
struct MileageProgressView: View {
    @Environment(AppState.self) private var app
    private var first: FillUp? { app.fillUps.first }
    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    MileageDiagram(firstLogged: true, firstLabel: "Today · \((first?.odo ?? 18058).formatted()) km").padding(.top, 62)
                    StatusPill(text: "1 of 2 fill-ups logged", on: true).padding(.top, 14).padding(.leading, 4)
                    Text("One more fill-up\nand you’re set").cvText(28, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.5, lineHeight: 34, inter: true).padding(.top, 14)
                    Text("Ride as usual. Next time you fill the tank to full, log it here and your km/l shows up.").cvText(15, color: CV.cream.opacity(0.55), lineHeight: 21, inter: true).padding(.top, 8)
                    HStack(spacing: 12) {
                        Image(systemName: "fuelpump").foregroundStyle(CV.red).frame(width: 40, height: 40).background(CV.red.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Fill-up 1 · Today, 9:41 AM").cvText(15, .semibold, inter: true)
                            Text("\((first?.odo ?? 18058).formatted()) km · \(String(format: "%.1f", first?.litres ?? 12.4)) L · ₹\(Int(((first?.litres ?? 12.4) * (first?.price ?? 102.9)).rounded()).formatted())").cvText(12, color: CV.cream.opacity(0.5), inter: true)
                        }
                        Spacer(); Text("Edit").cvText(13, .semibold, color: CV.cream.opacity(0.6), inter: true)
                    }.padding(.horizontal, 16).frame(height: 72).background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).padding(.top, 24)
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles").foregroundStyle(Color(hex: 0xFFB020)).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tip for a true number").cvText(14, .bold, color: Color(hex: 0xFFB020), inter: true)
                            Text("Fill until the nozzle clicks off, at the same pump if you can.").cvText(13, color: CV.cream.opacity(0.6), lineHeight: 18, inter: true)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xFFB020).opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color(hex: 0xFFB020).opacity(0.3), lineWidth: 1)).padding(.top, 12)
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
            GarageNav(title: "Mileage") { Color.clear.frame(width: 44) }
        }
        .safeAreaInset(edge: .bottom) { PrimaryButton(title: "Log fill-up 2") { app.push(.logFillUp) }.padding(.horizontal, 20).padding(.bottom, 8) }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
}

/// G06 · Mileage results.
struct MileageResultsView: View {
    @Environment(AppState.self) private var app
    private let bars: [(String, Double)] = [("2 Aug", 35.1), ("19 Aug", 36.0), ("6 Sep", 37.4), ("24 Sep", 35.7), ("9 Oct", 36.8)]

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("YOUR APPROX MILEAGE").cvText(11, .semibold, color: CV.cream.opacity(0.55), tracking: 0.5, inter: true)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("36.2").cvText(72, .bold, tracking: -2, inter: true); Text("km/l").cvText(20, .medium, color: CV.cream.opacity(0.55), inter: true)
                        }.padding(.top, 4)
                        HStack {
                            Text("▲ 0.6 vs last fill-up").cvText(12, .semibold, color: CV.green, inter: true).padding(.horizontal, 12).frame(height: 25).background(CV.green.opacity(0.18), in: Capsule())
                            Spacer(); Text("5 fill-ups · 1,860 km").cvText(12, color: CV.cream.opacity(0.55), inter: true)
                        }.padding(.top, 6)
                    }
                    .padding(20).background(LinearGradient(colors: [CV.red.opacity(0.2), panel], startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1)).padding(.top, 62)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack { Text("Last 5 fill-ups").cvText(15, .bold, inter: true); Spacer(); Text("- - avg 36.2 km/l").cvText(12, color: CV.cream.opacity(0.55), inter: true) }
                        Chart {
                            ForEach(bars, id: \.0) { b in
                                BarMark(x: .value("Date", b.0), y: .value("km/l", b.1), width: .fixed(34)).cornerRadius(10)
                                    .foregroundStyle(b.0 == "9 Oct" ? CV.red : Color(hex: 0x3A3A3E))
                                    .annotation(position: .top, spacing: 4) { Text(String(format: "%.1f", b.1)).font(.system(size: 11, weight: .semibold)).foregroundStyle(b.0 == "9 Oct" ? CV.cream : CV.cream.opacity(0.55)) }
                            }
                            RuleMark(y: .value("avg", 36.2)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(CV.cream.opacity(0.4))
                        }
                        .chartYScale(domain: 0...40).chartYAxis(.hidden)
                        .chartXAxis { AxisMarks { v in AxisValueLabel().foregroundStyle(CV.cream.opacity(0.5)).font(.system(size: 11)) } }
                        .frame(height: 150).padding(.top, 14)
                    }
                    .padding(18).background(panel, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).padding(.top, 14)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        tile("FULL-TANK RANGE", "≈ 470 km", "on 13 L"); tile("COST PER KM", "₹2.84", "at ₹102.90 / L")
                        tile("BEST TANK", "37.4 km/l", "6 Sep · highway"); tile("FUEL THIS MONTH", "₹2,550", "2 fill-ups")
                    }.padding(.top, 16)

                    HStack { Text("FILL-UPS").cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.5, inter: true); Spacer(); Text("See all").cvText(13, .semibold, color: CV.red, inter: true) }.padding(.top, 24).padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        row("9 Oct · HP, Hebbal", "12.1 L · ₹1,245 · full tank", "36.8"); line
                        row("24 Sep · IOCL, Yelahanka", "12.6 L · ₹1,297 · full tank", "35.7"); line
                        row("6 Sep · Shell, Devanahalli", "11.9 L · ₹1,236 · full tank", "37.4")
                    }.background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).padding(.top, 8)
                }.padding(.horizontal, 20).padding(.bottom, 110)
            }.scrollIndicators(.hidden)
            GarageNav(title: "Mileage") { Color.clear.frame(width: 44) }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Log fill-up") { app.fillUps = Array(app.fillUps.prefix(1)); app.push(.logFillUp) }.padding(.horizontal, 20).padding(.bottom, 8)
                .background(LinearGradient(colors: [CV.bg.opacity(0), CV.bg], startPoint: .top, endPoint: .bottom))
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
    private var line: some View { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 68) }
    private func tile(_ t: String, _ v: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).cvText(11, .semibold, color: CV.cream.opacity(0.5), tracking: 0.5, inter: true)
            Text(v).cvText(20, .bold, inter: true)
            Text(s).cvText(11, color: CV.cream.opacity(0.5), inter: true)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).frame(height: 84)
        .background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }
    private func row(_ t: String, _ s: String, _ v: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "fuelpump").font(.system(size: 15)).foregroundStyle(CV.cream.opacity(0.8)).frame(width: 40, height: 40).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) { Text(t).cvText(14, .semibold, inter: true); Text(s).cvText(12, color: CV.cream.opacity(0.5), inter: true) }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) { Text(v).cvText(15, .bold, inter: true); Text("km/l").cvText(11, color: CV.cream.opacity(0.5), inter: true) }
        }.padding(.horizontal, 16).frame(height: 64)
    }
}
