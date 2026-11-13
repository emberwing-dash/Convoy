import SwiftUI

// MARK: - Enums

enum GarageTopTab: String, CaseIterable { case bike = "Bike", gear = "Gear" }

enum GarageSubTab: String, CaseIterable {
    case info = "Info", docs = "Docs", service = "Service", accessories = "Accessories", costs = "Costs"
    var icon: String {
        switch self {
        case .info: "info.circle.fill"
        case .docs: "checkmark.shield.fill"
        case .service: "wrench.and.screwdriver.fill"
        case .accessories: "wrench.fill"
        case .costs: "indianrupeesign.circle.fill"
        }
    }
}

private let panel = Color(hex: 0x1C1C1F)
private let amber = Color(hex: 0xFFB020)

// ───────────────────────────────────────────────
// MARK: - GarageNav (kept for DocumentView etc.)
// ───────────────────────────────────────────────

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

// ───────────────────────────────────────────────
// MARK: - GarageView  (matches ref/garage images)
// ───────────────────────────────────────────────

struct GarageView: View {
    @Environment(AppState.self) private var app
    @State private var store = GarageStore.shared

    @State private var topTab: GarageTopTab = .bike
    @State private var subTab: GarageSubTab = .info
    @State private var selectedBikeIndex = 0

    // sheets / alerts
    @State private var showAddBike   = false
    @State private var showAddGear   = false
    @State private var showAddAccessory = false
    @State private var showEditBike  = false
    @State private var showUploadDoc: DocType? = nil
    @State private var showReportImage = false

    private var bike: GarageBike? {
        guard !store.bikes.isEmpty else { return nil }
        return store.bikes[min(max(0, selectedBikeIndex), store.bikes.count - 1)]
    }

    var body: some View {
        ZStack(alignment: .top) {
            // deep-red → black gradient background
            LinearGradient(colors: [Color(hex: 0x360808), Color(hex: 0x1A0507), CV.bg],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header.padding(.horizontal, 20).padding(.top, 12)
                topToggle.padding(.horizontal, 20).padding(.top, 14)

                if topTab == .bike {
                    bikeCarousel.padding(.top, 14)
                    subTabBar.padding(.horizontal, 20).padding(.top, 12)

                    ScrollView {
                        VStack(spacing: 16) {
                            if let b = bike {
                                switch subTab {
                                case .info:        infoTab(b)
                                case .docs:        docsTab(b)
                                case .service:     serviceTab(b)
                                case .accessories: accessoriesTab(b)
                                case .costs:       costsTab(b)
                                }
                            } else { noBikePlaceholder }
                        }
                        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 120)
                    }.scrollIndicators(.hidden)
                } else {
                    ScrollView {
                        gearTab.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 120)
                    }.scrollIndicators(.hidden)
                }
            }
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAddBike) {
            AddBikeFlowView { b in store.addBike(b); selectedBikeIndex = 0 }
        }
        .sheet(isPresented: $showAddGear) {
            QuickGearAddSheet { g in store.addGear(g) }
        }
        .sheet(isPresented: $showAddAccessory) {
            if let b = bike {
                AddAccessorySheet(bikeId: b.id) { a in store.addAccessory(a) }
            }
        }
        .sheet(isPresented: $showEditBike) {
            if let b = bike {
                EditBikeDetailsSheet(bike: b) { u in store.updateBike(u) }
            }
        }
        .sheet(item: $showUploadDoc) { dt in
            if let b = bike {
                UploadDocSheet(bikeId: b.id, docType: dt) { d in store.addDoc(d) }
            }
        }
        .alert("Report Motorcycle Image", isPresented: $showReportImage) {
            Button("Submit Correct Photo") {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Thanks! We'll update the photo for \(bike?.displayName ?? "this bike").")
        }
    }

    // MARK: Header ─────────────────────────

    private var header: some View {
        HStack {
            if !app.path.isEmpty {
                CircleBackButton { app.pop() }
            }
            Text("Garage").cvText(32, .bold, color: CV.cream, inter: true)
            Spacer()
            // alert triangle
            ZStack {
                Circle().fill(Color(hex: 0x3E1E21)).frame(width: 44, height: 44)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF453A))
            }
            // avatar
            ZStack {
                Circle().fill(Color(hex: 0x3E535F)).frame(width: 44, height: 44)
                Text("G").cvText(18, .bold, color: CV.cream, inter: true)
            }
        }
    }

    // MARK: Bike / Gear Toggle ─────────────

    private var topToggle: some View {
        HStack(spacing: 4) {
            pill(.bike, icon: "bicycle",     active: Color(hex: 0x932018))
            pill(.gear, icon: "shield.fill", active: Color(hex: 0x944F27))
        }
        .padding(4)
        .background(Color(hex: 0x221214), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func pill(_ tab: GarageTopTab, icon: String, active: Color) -> some View {
        let on = topTab == tab
        return Button {
            withAnimation(.snappy(duration: 0.25)) { topTab = tab }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold))
                Text(tab.rawValue).cvText(16, .semibold, inter: true)
            }
            .foregroundStyle(on ? .white : CV.cream.opacity(0.6))
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(on ? active : .clear, in: Capsule())
            .overlay(on ? Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1) : nil)
        }.buttonStyle(.plain)
    }

    // MARK: Bike Carousel ──────────────────

    private var bikeCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(store.bikes.enumerated()), id: \.element.id) { i, b in
                    let on = i == selectedBikeIndex
                    Button { withAnimation(.snappy(duration: 0.2)) { selectedBikeIndex = i } } label: {
                        VStack(spacing: 8) {
                            SmallBikeThumb(make: b.make, model: b.model, year: b.year).frame(height: 38)
                            Text("\(b.make)\n\(b.model)")
                                .cvText(11, on ? .bold : .medium, color: on ? CV.cream : CV.muted, inter: true)
                                .multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: 80)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 10)
                        .frame(width: 96, height: 96)
                        .background(on ? Color(hex: 0x471A1D) : Color.white.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(on ? Color(hex: 0xC4382E) : Color.white.opacity(0.06),
                                          lineWidth: on ? 1.5 : 1))
                    }.buttonStyle(.plain)
                }

                // + add bike
                Button { showAddBike = true } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 20, weight: .bold)).foregroundStyle(Color(hex: 0xC4382E))
                        Text("Add Bike").cvText(11, .semibold, color: CV.cream.opacity(0.8), inter: true)
                    }
                    .frame(width: 80, height: 96)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }.buttonStyle(.plain)
            }.padding(.horizontal, 20)
        }
    }

    // MARK: Sub-tab bar ────────────────────

    private var subTabBar: some View {
        HStack(spacing: 4) {
            ForEach(GarageSubTab.allCases, id: \.self) { t in
                let on = subTab == t
                Button { withAnimation(.snappy(duration: 0.2)) { subTab = t } } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(.system(size: 15, weight: .semibold))
                        Text(t.rawValue).cvText(11, on ? .bold : .medium, inter: true)
                    }
                    .foregroundStyle(on ? CV.cream : CV.cream.opacity(0.5))
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(on ? Color(hex: 0x472322) : .clear,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(hex: 0x27191C), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    // ─────────────────────────────────────────
    // MARK: ■ Info Tab
    // ─────────────────────────────────────────

    @ViewBuilder private func infoTab(_ b: GarageBike) -> some View {
        // Hero image from CarImagesAPI (motorcycle-only)
        BikeImageView(make: b.make, model: b.model, year: b.year, height: 210)
            .frame(maxWidth: .infinity)

        Button { showReportImage = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left").font(.system(size: 13))
                Text("Wrong image? Report & submit a photo")
                    .cvText(12, .medium, color: CV.cream.opacity(0.6), inter: true)
            }
        }.buttonStyle(.plain)

        // 3 stat cards
        HStack(spacing: 10) {
            statCard("bolt.fill",       fmt(b.powerBHP),  "BHP", "POWER")
            statCard("sun.max.fill",    fmt(b.torqueNM),  "NM",  "TORQUE")
            statCard("scalemass.fill",  "\(b.weightKG ?? 0)", "KG", "WEIGHT")
        }

        // SPECIFICATIONS
        specCard(b)

        // YOUR BIKE
        yourBikeCard(b)

        // LINEAGE
        if let lin = b.lineage {
            sectionCard("LINEAGE", icon: "arrow.triangle.2.circlepath") {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 13)).foregroundStyle(CV.red)
                    Text("REPLACES").cvText(10, .bold, color: CV.cream.opacity(0.5), tracking: 0.5, inter: true)
                }
                Text(lin).cvText(15, .bold, color: CV.cream, inter: true)
            }
        }

        // ABOUT THIS GENERATION
        if let about = b.aboutGeneration {
            sectionCard("ABOUT THIS GENERATION", icon: "doc.text.fill") {
                Text(about).cvText(14, color: CV.cream.opacity(0.8), inter: true).lineSpacing(4)
            }
        }

        // AVAILABLE COLOURS
        if !b.availableColors.isEmpty {
            sectionCard("AVAILABLE COLOURS", icon: "paintpalette.fill") {
                FlowLayout(spacing: 6) {
                    ForEach(b.availableColors, id: \.self) { c in
                        Text(c).cvText(13, .medium, inter: true)
                            .padding(.horizontal, 12).frame(height: 30)
                            .background(Color.white.opacity(0.06), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    }
                }
            }
        }

        // Edit button
        Button { showEditBike = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "pencil").font(.system(size: 14, weight: .bold))
                Text("Edit Details").cvText(15, .bold, color: CV.red, inter: true)
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(panel, in: Capsule())
            .overlay(Capsule().strokeBorder(CV.red, lineWidth: 1.5))
        }.buttonStyle(.plain).padding(.top, 6)
    }

    // helpers
    private func fmt(_ d: Double?) -> String {
        guard let d else { return "—" }
        return d == d.rounded() ? "\(Int(d))" : String(format: "%.1f", d)
    }

    private func statCard(_ icon: String, _ val: String, _ unit: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(CV.red)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(val).cvText(22, .bold, color: CV.cream, inter: true)
                Text(unit).cvText(11, .semibold, color: CV.muted, inter: true)
            }
            Text(label).cvText(11, .bold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x241F23), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func specCard(_ b: GarageBike) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.2.fill").font(.system(size: 14)).foregroundStyle(CV.red)
                Text("SPECIFICATIONS").cvText(12, .bold, color: CV.cream.opacity(0.6), tracking: 0.8, inter: true)
            }
            specRow("square.grid.2x2.fill", "CATEGORY",    b.category ?? "—")
            specRow("gearshape.fill",       "ENGINE",      "\(b.engineCC ?? 0)cc · \(b.fuelType ?? "Petrol")")
            specRow("bolt.fill",            "POWER",       "\(fmt(b.powerBHP)) bhp")
            specRow("sun.max.fill",         "TORQUE",      "\(fmt(b.torqueNM)) Nm")
            specRow("fuelpump.fill",        "MILEAGE",     "\(fmt(b.mileageKMPL)) kmpl")
            specRow("drop.fill",            "TANK",        "\(fmt(b.tankL)) L")
            specRow("scalemass.fill",       "KERB WEIGHT", "\(b.weightKG ?? 0) kg")
            if let ts = b.topSpeedKMH { specRow("speedometer", "TOP SPEED", "\(ts) km/h") }
        }
        .padding(20)
        .background(Color(hex: 0x1E1B1D), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func specRow(_ icon: String, _ label: String, _ val: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(CV.red).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).cvText(10, .bold, color: CV.cream.opacity(0.45), tracking: 0.6, inter: true)
                Text(val).cvText(15, .bold, color: CV.cream, inter: true)
            }
            Spacer()
        }
    }

    private func yourBikeCard(_ b: GarageBike) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(CV.red)
                Text("YOUR BIKE").cvText(12, .bold, color: CV.cream.opacity(0.6), tracking: 0.8, inter: true)
            }

            HStack(spacing: 12) {
                Image(systemName: "calendar").font(.system(size: 15)).foregroundStyle(CV.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("YEAR").cvText(10, .bold, color: CV.cream.opacity(0.5), tracking: 0.5, inter: true)
                    Text("\(b.year)").cvText(16, .bold, color: CV.cream, inter: true)
                }; Spacer()
            }

            HStack(spacing: 12) {
                Image(systemName: "gauge.with.needle.fill").font(.system(size: 15)).foregroundStyle(CV.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ODOMETER").cvText(10, .bold, color: CV.cream.opacity(0.5), tracking: 0.5, inter: true)
                    Text(b.odometer != nil ? "\(b.odometer!) km" : "Not set — tap to add")
                        .cvText(14, .semibold, color: b.odometer != nil ? CV.cream : CV.red, inter: true)
                }; Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.red)
            }

            if let reg = b.regNumber {
                HStack(spacing: 12) {
                    Image(systemName: "car.fill").font(.system(size: 15)).foregroundStyle(CV.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("REG NUMBER").cvText(10, .bold, color: CV.cream.opacity(0.5), tracking: 0.5, inter: true)
                        Text(reg).cvText(14, .bold, color: CV.cream, inter: true)
                    }; Spacer()
                }
            }
        }
        .padding(20)
        .background(Color(hex: 0x1E1B1D), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func sectionCard<C: View>(_ title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(CV.red)
                Text(title).cvText(12, .bold, color: CV.cream.opacity(0.6), tracking: 0.8, inter: true)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(hex: 0x1E1B1D), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    // ─────────────────────────────────────────
    // MARK: ■ Docs Tab
    // ─────────────────────────────────────────

    @ViewBuilder private func docsTab(_ b: GarageBike) -> some View {
        let dd = store.docs(for: b.id)
        let comp = dd.filter { !$0.isExpired }.count
        let pct = min(100, dd.isEmpty ? 0 : Int(Double(comp) / 3.0 * 100))

        // compliance banner
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 28)).foregroundStyle(CV.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Compliance Status").cvText(17, .bold, color: CV.cream, inter: true)
                Text("Compliant").cvText(13, color: CV.muted, inter: true)
            }
            Spacer()
            Text("\(pct)%").cvText(28, .bold, color: CV.green, inter: true)
        }
        .padding(20)
        .background(Color(hex: 0x1A261D).opacity(0.7), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(CV.green.opacity(0.4), lineWidth: 1))

        // doc cards
        docCard("Insurance",        .insurance, "shield.fill",  CV.green, dd)
        docCard("PUC Certificate",  .puc,       "leaf.fill",    Color(hex: 0x32ADE6), dd)
        docCard("RC (Registration)",.rc,        "doc.fill",     Color(hex: 0x007AFF), dd)
    }

    private func docCard(_ title: String, _ type: DocType, _ icon: String, _ color: Color, _ docs: [BikeDocument]) -> some View {
        let existing = docs.first(where: { $0.type == type })
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(color)
                Text(title).cvText(17, .bold, color: CV.cream, inter: true)
                Spacer()
                if let d = existing {
                    badge(d.noExpiry ? "✓ No Expiry" : d.isExpired ? "Expired" : d.isExpiringSoon ? "\(d.daysUntilExpiry ?? 0) days" : "Active",
                          d.isExpired ? .red : d.isExpiringSoon ? amber : CV.green)
                } else {
                    badge("No Expiry", CV.cream.opacity(0.6))
                }
            }
            Button { showUploadDoc = type } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 16))
                    Text(existing != nil ? "Update \(title)" : "Upload \(title)")
                        .cvText(14, .semibold, inter: true)
                }
                .foregroundStyle(Color(hex: 0x32ADE6))
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Color(hex: 0x182633), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }.buttonStyle(.plain)
        }
        .padding(18).background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).cvText(12, .semibold, color: color, inter: true)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.16), in: Capsule())
    }

    // ─────────────────────────────────────────
    // MARK: ■ Service Tab
    // ─────────────────────────────────────────

    @ViewBuilder private func serviceTab(_ b: GarageBike) -> some View {
        let items = store.services(for: b.id)

        HStack { Text("Service History").cvText(20, .bold, color: CV.cream, inter: true); Spacer() }

        // next service card
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next Scheduled Service").cvText(17, .bold, color: CV.cream, inter: true)
                    Text("in 340 km · recommended service check").cvText(13, color: CV.cream.opacity(0.6), inter: true)
                }; Spacer()
                badge("Due Soon", amber)
            }
            HStack(spacing: 16) {
                svcCheck("Engine Oil", "Replace", amber)
                svcCheck("Air Filter", "Clean", CV.green)
                svcCheck("Chain Lube", "OK", CV.green)
            }.padding(.top, 8)
        }
        .padding(18).background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))

        if items.isEmpty {
            emptyBlock("wrench.and.screwdriver", "No service logs yet",
                       "Keep your motorcycle running smooth by logging oil changes and tune-ups.")
        } else {
            ForEach(items) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title).cvText(15, .bold, color: CV.cream, inter: true)
                        Text(s.date.formatted(date: .abbreviated, time: .omitted)).cvText(12, color: CV.muted, inter: true)
                    }; Spacer()
                    if let km = s.odometerKM { Text("\(km) km").cvText(14, .semibold, color: CV.cream, inter: true) }
                }
                .padding(14).background(panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func svcCheck(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).cvText(12, color: CV.muted, inter: true)
            HStack(spacing: 5) { Circle().fill(c).frame(width: 6, height: 6); Text(v).cvText(13, .semibold, color: c, inter: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    // ─────────────────────────────────────────
    // MARK: ■ Accessories Tab
    // ─────────────────────────────────────────

    @ViewBuilder private func accessoriesTab(_ b: GarageBike) -> some View {
        let items = store.accessories(for: b.id)

        HStack {
            Text("Installed Accessories").cvText(20, .bold, color: CV.cream, inter: true); Spacer()
            Button { showAddAccessory = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("Add").cvText(13, .bold, inter: true)
                }
                .foregroundStyle(amber).padding(.horizontal, 14).frame(height: 32)
                .background(Color(hex: 0x3B2813), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }.buttonStyle(.plain)
        }

        if items.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "wrench.fill").font(.system(size: 40)).foregroundStyle(amber).padding(.top, 24)
                Text("No accessories installed").cvText(18, .bold, color: CV.cream, inter: true)
                Text("Add phone mounts, lights, exhaust upgrades\nand more").cvText(14, color: CV.muted, inter: true).multilineTextAlignment(.center)
                Button { showAddAccessory = true } label: {
                    Text("Add Accessory").cvText(16, .bold, color: .black, inter: true)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(amber, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain).padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        } else {
            ForEach(items) { acc in
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x3B2813)).frame(width: 44, height: 44)
                        Image(systemName: "wrench.fill").font(.system(size: 18)).foregroundStyle(amber)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(acc.name).cvText(16, .bold, color: CV.cream, inter: true)
                        if let br = acc.brand { Text(br).cvText(12, color: CV.muted, inter: true) }
                    }; Spacer()
                    if let c = acc.cost { Text("₹\(Int(c))").cvText(15, .bold, color: CV.cream, inter: true) }
                }.padding(14).background(panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    // ─────────────────────────────────────────
    // MARK: ■ Costs Tab
    // ─────────────────────────────────────────

    @ViewBuilder private func costsTab(_ b: GarageBike) -> some View {
        let items = store.costs(for: b.id)
        let total = items.reduce(0) { $0 + $1.amount }

        HStack { Text("Bike Expenses").cvText(20, .bold, color: CV.cream, inter: true); Spacer() }

        VStack(alignment: .leading, spacing: 10) {
            Text("TOTAL SPENT").cvText(11, .bold, color: CV.cream.opacity(0.5), tracking: 0.8, inter: true)
            Text("₹\(Int(total))").cvText(36, .bold, color: CV.cream, inter: true)
            Text("Fuel, maintenance, parts & insurance").cvText(12, color: CV.muted, inter: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))

        if items.isEmpty {
            emptyBlock("indianrupeesign.circle", "No expenses logged yet", "Track your fuel receipts and servicing bills.")
        } else {
            ForEach(items) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.category).cvText(15, .bold, color: CV.cream, inter: true)
                        Text(c.date.formatted(date: .abbreviated, time: .omitted)).cvText(12, color: CV.muted, inter: true)
                    }; Spacer()
                    Text("₹\(Int(c.amount))").cvText(16, .bold, color: CV.cream, inter: true)
                }.padding(14).background(panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // ─────────────────────────────────────────
    // MARK: ■ Gear Tab
    // ─────────────────────────────────────────

    private var gearTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Text("My Gear").cvText(22, .bold, color: CV.cream, inter: true)
                Text("\(store.gearItems.count)").cvText(13, .bold, color: .black, inter: true)
                    .padding(.horizontal, 10).padding(.vertical, 3).background(amber, in: Capsule())
                Spacer()
                Button { showAddGear = true } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x3B2516)).frame(width: 38, height: 38)
                        Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(amber)
                    }
                }.buttonStyle(.plain)
            }

            Text("RIDING GEAR  \(store.gearItems.count)")
                .cvText(12, .bold, color: CV.cream.opacity(0.5), tracking: 0.8, inter: true)

            if store.gearItems.isEmpty {
                emptyBlock("shield", "No gear added yet", "Keep tabs on helmets, jackets, gloves, boots and warranty expiry.")
            } else {
                ForEach(store.gearItems) { g in
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x3B2516)).frame(width: 52, height: 52)
                            Image(systemName: g.type.sfIcon).font(.system(size: 20)).foregroundStyle(amber)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(g.name).cvText(17, .bold, color: CV.cream, inter: true)
                            Text(g.condition.rawValue).cvText(13, color: CV.muted, inter: true)
                        }; Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.cream.opacity(0.4))
                    }
                    .padding(14)
                    .background(panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                }
            }
        }
    }

    // shared empty state
    private func emptyBlock(_ icon: String, _ title: String, _ sub: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 32)).foregroundStyle(CV.muted).padding(.top, 16)
            Text(title).cvText(15, .semibold, color: CV.cream, inter: true)
            Text(sub).cvText(13, color: CV.muted, inter: true).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var noBikePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "motorcycle").font(.system(size: 44)).foregroundStyle(CV.red).padding(.top, 30)
            Text("No bikes in garage").cvText(18, .bold, color: CV.cream, inter: true)
            Text("Add your motorcycle to view specifications, docs and costs.")
                .cvText(14, color: CV.muted, inter: true).multilineTextAlignment(.center).padding(.horizontal, 24)
            Button { showAddBike = true } label: {
                Text("+ Add a Bike").cvText(16, .bold, color: .white, inter: true)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(CV.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }.buttonStyle(.plain).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 30)
        }.frame(maxWidth: .infinity).background(panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// FlowLayout is defined in RoutesViews.swift — reused here for colour chips.

// ───────────────────────────────────────────────
// MARK: - Add Bike Flow  (matches ref: Select → Confirm)
// ───────────────────────────────────────────────

struct AddBikeFlowView: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (GarageBike) -> Void

    @State private var search = ""
    @State private var picked: CatalogBike?
    @State private var nickname = ""

    private var filtered: [CatalogBike] {
        guard !search.isEmpty else { return popularBikesCatalog }
        return popularBikesCatalog.filter {
            $0.make.localizedCaseInsensitiveContains(search) ||
            $0.model.localizedCaseInsensitiveContains(search) ||
            "\($0.engineCC)".contains(search)
        }
    }

    var body: some View {
        ZStack {
            Color(hex: 0x120808).ignoresSafeArea()
            if let b = picked { confirmView(b) } else { selectView }
        }
    }

    private var selectView: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }.cvText(15, .semibold, color: amber, inter: true)
                Spacer(); Text("Add a Bike").cvText(17, .bold, color: CV.cream, inter: true); Spacer()
                Color.clear.frame(width: 50)
            }.padding(.horizontal, 20).padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Select Your Bike").cvText(22, .bold, color: CV.cream, inter: true).padding(.top, 8)

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(CV.muted)
                        TextField("Try \"Duke 390\", \"Royal Enfield\", \"150cc\"", text: $search).foregroundStyle(CV.cream)
                    }
                    .padding(.horizontal, 16).frame(height: 48)
                    .background(Color(hex: 0x221316), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    HStack(spacing: 8) { chip("⭐ Popular"); chip("🔥 Trending"); chip("⚡ Electric") }

                    let brands = ["Honda","KTM","Hero MotoCorp","Bajaj","Triumph","Ducati","TVS","BMW","Kawasaki","Royal Enfield","Yamaha","Harley-Davidson"]
                    Text("POPULAR BRANDS").cvText(11, .bold, color: CV.cream.opacity(0.5), tracking: 0.8, inter: true)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(brands, id: \.self) { b in
                            Button { search = b } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "motorcycle.fill").font(.system(size: 22)).foregroundStyle(CV.red)
                                    Text(b).cvText(12, .semibold, color: CV.cream, inter: true).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity).frame(height: 76)
                                .background(Color(hex: 0x221316), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }

                    Text("POPULAR IN INDIA").cvText(11, .bold, color: CV.cream.opacity(0.5), tracking: 0.8, inter: true)
                    ForEach(filtered) { b in
                        Button { withAnimation { picked = b } } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x16344A)).frame(width: 48, height: 48)
                                    Image(systemName: "motorcycle").font(.system(size: 22)).foregroundStyle(Color(hex: 0x32ADE6))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(b.make).cvText(12, color: CV.muted, inter: true)
                                    Text(b.model).cvText(16, .bold, color: CV.cream, inter: true)
                                    Text(b.categoryAndCC).cvText(12, color: CV.muted, inter: true)
                                }; Spacer()
                            }
                            .padding(14).background(Color(hex: 0x221316), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20).padding(.bottom, 30)
            }.scrollIndicators(.hidden)
        }
    }

    private func chip(_ t: String) -> some View {
        Text(t).cvText(13, .semibold, color: CV.cream, inter: true)
            .padding(.horizontal, 14).frame(height: 36)
            .background(Color(hex: 0x221316), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func confirmView(_ b: CatalogBike) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }.cvText(15, .semibold, color: CV.muted, inter: true)
                Spacer(); Text("Confirm Bike").cvText(17, .bold, color: CV.cream, inter: true); Spacer()
                Color.clear.frame(width: 50)
            }.padding(.horizontal, 20).padding(.top, 16)

            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    // Show real motorcycle image from API
                    BikeImageView(make: b.make, model: b.model, height: 140)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)

                    VStack(spacing: 6) {
                        Text("\(b.make) \(b.model)").cvText(22, .bold, color: CV.cream, inter: true).multilineTextAlignment(.center)
                        HStack(spacing: 6) {
                            Image(systemName: "bicycle")
                            Text("\(b.category)  \(b.engineCC)cc")
                        }.cvText(14, color: CV.muted, inter: true)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 32)
                .background(Color(hex: 0x241417), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Nickname (optional)").cvText(14, .bold, color: CV.cream, inter: true)
                    TextField("e.g., My Daily Rider", text: $nickname)
                        .padding(.horizontal, 16).frame(height: 52)
                        .background(Color(hex: 0x241417), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(CV.cream)
                }

                Button {
                    let g = GarageBike(make: b.make, model: b.model, year: 2026,
                                       nickname: nickname.isEmpty ? nil : nickname,
                                       category: b.category, engineCC: b.engineCC,
                                       fuelType: b.fuelType, powerBHP: b.powerBHP,
                                       torqueNM: b.torqueNM, weightKG: b.weightKG,
                                       tankL: b.tankL, mileageKMPL: b.mileageKMPL,
                                       topSpeedKMH: b.topSpeedKMH,
                                       aboutGeneration: b.aboutGeneration,
                                       lineage: b.lineage, availableColors: b.availableColors)
                    onAdd(g); dismiss()
                } label: {
                    HStack(spacing: 8) { Image(systemName: "plus.circle.fill"); Text("Add to Garage") }
                        .cvText(16, .bold, color: .white, inter: true)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(CV.red, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }.buttonStyle(.plain)

                Button { withAnimation { picked = nil } } label: {
                    HStack(spacing: 6) { Image(systemName: "chevron.left"); Text("Choose a different bike") }
                        .cvText(15, .semibold, color: amber, inter: true)
                }.buttonStyle(.plain)

                Spacer()
            }.padding(.horizontal, 20).padding(.top, 24)
        }
    }
}

// ───────────────────────────────────────────────
// MARK: - Quick Gear Add Sheet (matches ref purple modal)
// ───────────────────────────────────────────────

struct QuickGearAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (GearItem) -> Void

    @State private var gearType: GearType = .helmet
    @State private var name = ""
    @State private var amount = ""
    @State private var qty = 1
    @State private var brand = ""
    @State private var size = ""
    @State private var condition: GearCondition = .new
    @State private var hasWarranty = false
    @State private var purchaseDate = Date()

    private let purple = Color(hex: 0xD027EF)

    var body: some View {
        ZStack {
            Color(hex: 0x161218).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { dismiss() }.cvText(16, .semibold, color: CV.red, inter: true)
                    Spacer(); Text("Quick Gear Add").cvText(17, .bold, color: CV.cream, inter: true); Spacer()
                    Color.clear.frame(width: 50)
                }.padding(.horizontal, 20).padding(.top, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 14) {
                            ZStack { Circle().fill(purple).frame(width: 52, height: 52)
                                Image(systemName: "figure.walk").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Add Riding Gear").cvText(20, .bold, color: CV.cream, inter: true)
                                Text("Add to your gear collection").cvText(13, color: CV.muted, inter: true)
                            }
                        }.padding(.top, 8)

                        Text("Gear Type").cvText(14, .bold, color: CV.cream, inter: true)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                            ForEach(GearType.allCases, id: \.self) { t in
                                let on = gearType == t
                                Button { gearType = t } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: t.sfIcon).font(.system(size: 20))
                                        Text(t.rawValue).cvText(12, .semibold, inter: true)
                                    }
                                    .foregroundStyle(on ? .white : CV.cream.opacity(0.8))
                                    .frame(maxWidth: .infinity).frame(height: 72)
                                    .background(on ? purple : Color(hex: 0x242028), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }

                        gearField("Item Name", "e.g., AGV K6 Helmet", $name)

                        HStack(spacing: 12) {
                            gearField("Amount", "₹ Optional", $amount, kbd: .numberPad)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Qty").cvText(14, .bold, color: CV.cream, inter: true)
                                Text("\(qty)").cvText(17, .bold, color: CV.cream, inter: true)
                                    .frame(maxWidth: .infinity).frame(height: 52)
                                    .background(Color(hex: 0x242028), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }.frame(width: 90)
                        }

                        gearField("Brand (Optional)", "e.g., AGV, Alpinestars", $brand)

                        HStack(spacing: 12) {
                            gearField("Size", "L, XL, 42", $size)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Condition").cvText(14, .bold, color: CV.cream, inter: true)
                                Menu {
                                    ForEach(GearCondition.allCases, id: \.self) { c in Button(c.rawValue) { condition = c } }
                                } label: {
                                    HStack {
                                        Text(condition.rawValue).cvText(15, .bold, color: CV.cream, inter: true)
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 13)).foregroundStyle(CV.muted)
                                    }.padding(.horizontal, 16).frame(height: 52)
                                    .background(Color(hex: 0x242028), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "shield.lefthalf.filled").font(.system(size: 20)).foregroundStyle(purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Has Warranty").cvText(15, .bold, color: CV.cream, inter: true)
                                Text("Track warranty expiration").cvText(12, color: CV.muted, inter: true)
                            }; Spacer()
                            Toggle("", isOn: $hasWarranty).labelsHidden().tint(purple)
                        }.padding(16).background(Color(hex: 0x242028), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Button {
                            let g = GearItem(type: gearType,
                                             name: name.isEmpty ? gearType.rawValue : name,
                                             brand: brand.isEmpty ? nil : brand,
                                             size: size.isEmpty ? nil : size,
                                             condition: condition,
                                             cost: Double(amount),
                                             quantity: qty,
                                             hasWarranty: hasWarranty,
                                             purchaseDate: purchaseDate)
                            onSave(g); dismiss()
                        } label: {
                            HStack(spacing: 8) { Image(systemName: "bag.fill"); Text("Add to My Gear") }
                                .cvText(16, .bold, color: CV.ink, inter: true)
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .background(Color(hex: 0x8E8E93), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }.buttonStyle(.plain).padding(.top, 8).padding(.bottom, 30)
                    }.padding(.horizontal, 20)
                }.scrollIndicators(.hidden)
            }
        }
    }

    private func gearField(_ label: String, _ ph: String, _ text: Binding<String>, kbd: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).cvText(14, .bold, color: CV.cream, inter: true)
            TextField(ph, text: text).keyboardType(kbd)
                .padding(.horizontal, 16).frame(height: 52)
                .background(Color(hex: 0x242028), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(CV.cream)
        }
    }
}

// ───────────────────────────────────────────────
// MARK: - Edit / Upload / Add-Accessory Sheets
// ───────────────────────────────────────────────

struct EditBikeDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var bike: GarageBike; var onSave: (GarageBike) -> Void
    @State private var nick: String; @State private var reg: String; @State private var odo: String

    init(bike: GarageBike, onSave: @escaping (GarageBike) -> Void) {
        self.bike = bike; self.onSave = onSave
        _nick = State(initialValue: bike.nickname ?? "")
        _reg  = State(initialValue: bike.regNumber ?? "")
        _odo  = State(initialValue: bike.odometer.map { "\($0)" } ?? "")
    }

    var body: some View {
        ZStack {
            Color(hex: 0x1E1B1D).ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Button("Cancel") { dismiss() }.cvText(15, color: CV.muted, inter: true); Spacer()
                    Text("Edit Details").cvText(17, .bold, color: CV.cream, inter: true); Spacer()
                    Button("Save") {
                        var u = bike; u.nickname = nick.isEmpty ? nil : nick
                        u.regNumber = reg.isEmpty ? nil : reg; u.odometer = Int(odo)
                        onSave(u); dismiss()
                    }.cvText(15, .bold, color: CV.red, inter: true)
                }.padding(.horizontal, 20).padding(.top, 16)
                VStack(spacing: 16) {
                    editField("NICKNAME", $nick, "e.g., Daily Commute")
                    editField("REGISTRATION NUMBER", $reg, "e.g., KA 01 RK 3500")
                    editField("ODOMETER (KM)", $odo, "e.g., 18420", kbd: .numberPad)
                }.padding(.horizontal, 20).padding(.top, 10)
                Spacer()
            }
        }
    }
    private func editField(_ lbl: String, _ txt: Binding<String>, _ ph: String, kbd: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lbl).cvText(11, .bold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
            TextField(ph, text: txt).keyboardType(kbd)
                .padding(.horizontal, 16).frame(height: 50)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(CV.cream)
        }
    }
}

struct UploadDocSheet: View {
    @Environment(\.dismiss) private var dismiss
    let bikeId: UUID; let docType: DocType; var onAdd: (BikeDocument) -> Void
    @State private var noExpiry = false
    @State private var expiry = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

    var body: some View {
        ZStack {
            Color(hex: 0x1E1B1D).ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Button("Cancel") { dismiss() }.cvText(15, color: CV.muted, inter: true); Spacer()
                    Text("Upload \(docType.rawValue)").cvText(17, .bold, color: CV.cream, inter: true); Spacer()
                    Button("Save") {
                        onAdd(BikeDocument(bikeId: bikeId, type: docType,
                                           expiryDate: noExpiry ? nil : expiry, noExpiry: noExpiry))
                        dismiss()
                    }.cvText(15, .bold, color: Color(hex: 0x32ADE6), inter: true)
                }.padding(.horizontal, 20).padding(.top, 16)
                VStack(spacing: 16) {
                    Toggle("No Expiration Date", isOn: $noExpiry).cvText(15, .semibold, color: CV.cream, inter: true).tint(Color(hex: 0x32ADE6))
                    if !noExpiry { DatePicker("Expiry Date", selection: $expiry, displayedComponents: .date).cvText(15, .semibold, color: CV.cream, inter: true) }
                }.padding(20).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous)).padding(.horizontal, 20)
                Spacer()
            }
        }
    }
}

struct AddAccessorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let bikeId: UUID; var onAdd: (AccessoryItem) -> Void
    @State private var name = ""; @State private var brand = ""; @State private var cost = ""

    var body: some View {
        ZStack {
            Color(hex: 0x1E1B1D).ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Button("Cancel") { dismiss() }.cvText(15, color: CV.muted, inter: true); Spacer()
                    Text("Add Accessory").cvText(17, .bold, color: CV.cream, inter: true); Spacer()
                    Button("Add") {
                        onAdd(AccessoryItem(bikeId: bikeId, name: name.isEmpty ? "Accessory" : name,
                                            brand: brand.isEmpty ? nil : brand, cost: Double(cost)))
                        dismiss()
                    }.cvText(15, .bold, color: Color(hex: 0xF59338), inter: true)
                }.padding(.horizontal, 20).padding(.top, 16)
                VStack(spacing: 14) {
                    accField("NAME", $name, "e.g., Bobo Phone Mount")
                    accField("BRAND", $brand, "e.g., Bobo, Maddog")
                    accField("COST (₹)", $cost, "e.g., 2500", kbd: .numberPad)
                }.padding(.horizontal, 20)
                Spacer()
            }
        }
    }
    private func accField(_ l: String, _ t: Binding<String>, _ p: String, kbd: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l).cvText(11, .bold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
            TextField(p, text: t).keyboardType(kbd).padding(.horizontal, 16).frame(height: 50)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous)).foregroundStyle(CV.cream)
        }
    }
}

// ───────────────────────────────────────────────
// MARK: - DocumentView  (kept for .document(name) route)
// ───────────────────────────────────────────────

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
                            Text("IL").cvText(18, .bold, color: CV.ink, inter: true)
                                .frame(width: 44, height: 44)
                                .background(Color(hex: 0xF5EDDE), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ICICI Lombard").cvText(18, .bold, inter: true)
                                Text("Comprehensive · Two-wheeler").cvText(12, color: CV.cream.opacity(0.55), inter: true)
                            }; Spacer()
                            Text("● Active").cvText(12, .semibold, color: CV.green, inter: true)
                                .padding(.horizontal, 10).frame(height: 25).background(CV.green.opacity(0.18), in: Capsule())
                        }
                        Text("POLICY NUMBER").cvText(11, .semibold, color: CV.cream.opacity(0.5), tracking: 0.5, inter: true).padding(.top, 22)
                        HStack {
                            Text("3005 / 2918 / 4471 / 00").cvText(17, .bold, inter: true); Spacer()
                            Text("Copy").cvText(13, .semibold, color: CV.cream.opacity(0.6), inter: true)
                        }.padding(.top, 4)
                        HStack {
                            Text("15 Mar 2026").cvText(12, color: CV.cream.opacity(0.55), inter: true); Spacer()
                            Text("14 Mar 2027").cvText(12, color: CV.cream.opacity(0.55), inter: true)
                        }.padding(.top, 18)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.15))
                                Capsule().fill(CV.cream).frame(width: g.size.width * 0.59)
                                Circle().fill(CV.cream).frame(width: 12, height: 12).offset(x: g.size.width * 0.59 - 6)
                            }
                        }.frame(height: 12).padding(.top, 6)
                        HStack { Text("151 days left").cvText(14, .semibold, inter: true); Spacer()
                            Text("Renews 14 Mar 2027").cvText(12, color: CV.cream.opacity(0.55), inter: true) }.padding(.top, 8)
                    }
                    .padding(18)
                    .background(LinearGradient(colors: [CV.red.opacity(0.18), panel], startPoint: .topTrailing, endPoint: .bottomLeading),
                                in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.top, 62)

                    Text("WHAT'S COVERED").cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.5, inter: true).padding(.top, 20).padding(.leading, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) { covChip("Own damage"); covChip("Third party") }
                        HStack(spacing: 8) { covChip("Zero depreciation"); covChip("Roadside assist") }
                    }.padding(.top, 8)

                    HStack(spacing: 12) {
                        Image(systemName: "bell").font(.system(size: 16)).foregroundStyle(amber)
                            .frame(width: 40, height: 40).background(amber.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Renewal reminder").cvText(15, .semibold, inter: true)
                            Text("30 days before · 12 Feb 2027").cvText(12, color: CV.cream.opacity(0.55), inter: true)
                        }; Spacer()
                        Toggle("", isOn: $reminder).labelsHidden().tint(CV.green)
                    }
                    .padding(.horizontal, 16).frame(height: 68)
                    .background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                    .padding(.top, 14)
                }.padding(.horizontal, 20).padding(.bottom, 110)
            }.scrollIndicators(.hidden)
            GarageNav(title: name) { Color.clear.frame(width: 44) }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                ShareLink(item: "\(name) · Classic 350 · KA 01 RK 3500") {
                    Text("Share").cvText(15, .semibold, inter: true).frame(width: 120, height: 52)
                        .background(panel, in: Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                }
                PrimaryButton(title: "View PDF").frame(height: 52)
            }.padding(.horizontal, 20).padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar).background(SwipeBackEnabler())
    }

    private func covChip(_ t: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(CV.green)
            Text(t).cvText(14, .medium, inter: true)
        }
        .padding(.horizontal, 14).frame(height: 34)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}
