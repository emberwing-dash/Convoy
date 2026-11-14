// PlanReviewView.swift
import SwiftUI
import MapKit
import CoreLocation

struct PlanReviewView: View {
    @Environment(AppState.self) private var app
    @FocusState private var focused: Bool
    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @State private var tempDate = Date()
    @State private var tempTime = Date()
    @State private var showNameError = false
    @State private var startPlaceDisplayName: String = ""

    private enum WaypointKind { case start, stop, end }

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Top Bar (Balanced, no awkward cutoffs)
                    HStack {
                        RoundIconButton(symbol: "chevron.left") { app.pop() }
                        Spacer()
                        Text("Trip Summary")
                            .cvText(16, .semibold, color: CV.cream.opacity(0.9), tracking: -0.2, inter: true)
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    .padding(.top, 4)
                    .safeAreaPadding(.top)

                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ride Confirmation")
                            .cvText(28, .bold, tracking: -0.6, inter: true)
                        Text("Review your details before initiating the ride.")
                            .cvText(15, color: CV.cream.opacity(0.65), inter: true)
                    }
                    .padding(.top, 4)

                    // 1. Ride Name at Top
                    FieldLabel(text: "RIDE NAME").padding(.top, 6)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("", text: $app.draft.name,
                                  prompt: Text(app.draft.to.isEmpty
                                               ? "e.g. Morning ride"
                                               : "e.g. Ride to \(shortPlace(app.draft.to))")
                                                .foregroundColor(CV.cream.opacity(0.40)))
                            .focused($focused)
                            .tint(Color(hex: 0xFF5C00))
                            .cvText(17, .semibold, tracking: -0.102, inter: true)
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                            .glassRounded(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(showNameError ? CV.red : Color.white.opacity(0.08), lineWidth: 1.5)
                            )
                            .onChange(of: app.draft.name) { _, _ in
                                if showNameError && !app.draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
                                    withAnimation { showNameError = false }
                                }
                            }
                        if showNameError {
                            Text("Please enter a name for your ride")
                                .cvText(13, color: CV.red, inter: true)
                                .padding(.leading, 16)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }

                    // 2. Dynamic Route Map
                    FieldLabel(text: "ROUTE & MAP").padding(.top, 8)
                    routeMap

                    // 3. Route Waypoints Card (Start, Stops, End with real place name)
                    routeWaypointsCard

                    // 4. When / Departure Time
                    FieldLabel(text: "WHEN").padding(.top, 8)
                    whenCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .ignoresSafeArea()
        .onTapGesture { focused = false }
        .sheet(isPresented: $showingDatePicker) { dateSheet }
        .sheet(isPresented: $showingTimePicker) { timeSheet }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Initiate plan") {
                focused = false
                let name = app.draft.name.trimmingCharacters(in: .whitespaces)
                if name.isEmpty {
                    withAnimation { showNameError = true }
                } else {
                    app.push(.planCreated)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .background(
                LinearGradient(colors: [CV.bg.opacity(0), CV.bg],
                               startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            )
        }
        .task {
            await resolveStartLocationName()
            if app.draft.selected == nil &&
               (!app.draft.from.isEmpty || app.draft.startCoord != nil) &&
               (!app.draft.to.isEmpty || app.draft.endCoord != nil) {
                await app.findRoutes()
            }
        }
    }

    // MARK: - Dynamic Route Map (GeometryReader-driven, adapts to all screen widths)

    private var routeMap: some View {
        GeometryReader { geo in
            let mapWidth = geo.size.width
            let mapHeight = geo.size.height

            ZStack(alignment: .top) {
                if let r = app.draft.selected {
                    RouteSnapshotView(coords: r.coords, size: CGSize(width: mapWidth, height: mapHeight))
                } else if let sc = app.draft.startCoord, let ec = app.draft.endCoord {
                    let waypoints = [sc] + app.draft.stopCoords + [ec]
                    RouteSnapshotView(coords: waypoints, size: CGSize(width: mapWidth, height: mapHeight))
                } else {
                    Rectangle().fill(Color(hex: 0x141416))
                }

                // Top shadow gradient for pill legibility
                LinearGradient(
                    colors: [Color.black.opacity(0.65), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 56)
                .allowsHitTesting(false)

                // Responsive Pills Overlay
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(app.draft.distanceText(app.draft.style)) · \(app.draft.durationText(app.draft.style))")
                            .cvText(12, .semibold, color: .white, inter: true)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color(hex: 0xFF5C00), in: Capsule())
                    .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 2)

                    Spacer(minLength: 8)

                    Button { app.popToLast(2) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Edit route")
                                .cvText(12, .semibold, color: .white, inter: true)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color(hex: 0x141416).opacity(0.9), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
            }
            .frame(width: mapWidth, height: mapHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .frame(height: 185)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Dynamic Route Waypoints Card

    private var routeWaypointsCard: some View {
        let startName = startPlaceDisplayName.isEmpty ? shortPlace(app.draft.from) : startPlaceDisplayName
        let endName = shortPlace(app.draft.to)
        let stops = app.draft.stops

        return VStack(spacing: 0) {
            // Start
            waypointRow(
                icon: .start,
                title: startName.isEmpty ? "Current Location" : startName,
                tag: "Start",
                showDivider: !stops.isEmpty || !endName.isEmpty
            )

            // Stops
            ForEach(Array(stops.enumerated()), id: \.offset) { idx, stopName in
                waypointRow(
                    icon: .stop,
                    title: shortPlace(stopName),
                    tag: stops.count > 1 ? "Stop \(idx + 1)" : "Stop",
                    showDivider: idx < stops.count - 1 || !endName.isEmpty
                )
            }

            // End
            waypointRow(
                icon: .end,
                title: endName.isEmpty ? "Destination" : endName,
                tag: "End",
                showDivider: false
            )
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func waypointRow(icon: WaypointKind, title: String, tag: String, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                switch icon {
                case .start:
                    Circle()
                        .strokeBorder(CV.cream, lineWidth: 3)
                        .frame(width: 14, height: 14)
                case .stop:
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(CV.cream, lineWidth: 2)
                        .frame(width: 14, height: 14)
                case .end:
                    ZStack {
                        Circle().fill(Color(hex: 0xFF5C00)).frame(width: 14, height: 14)
                        Circle().fill(.white).frame(width: 4, height: 4)
                    }
                }

                Text(title)
                    .cvText(16, .semibold, inter: true)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(tag)
                    .cvText(13, color: CV.cream.opacity(0.45), inter: true)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)

            if showDivider {
                HStack(spacing: 0) {
                    VStack(spacing: 3) {
                        Circle().fill(CV.cream.opacity(0.35)).frame(width: 2.5, height: 2.5)
                        Circle().fill(CV.cream.opacity(0.35)).frame(width: 2.5, height: 2.5)
                    }
                    .frame(width: 14)
                    .padding(.leading, 16)

                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .padding(.leading, 12)
                        .padding(.trailing, 16)
                }
                .frame(height: 8)
            }
        }
    }

    // MARK: - Location Reverse Geocoding

    private func resolveStartLocationName() async {
        let currentFrom = app.draft.from.trimmingCharacters(in: .whitespaces)

        // If user explicitly picked or typed a named location, keep it
        if !currentFrom.isEmpty && currentFrom.caseInsensitiveCompare("Current Location") != .orderedSame {
            startPlaceDisplayName = shortPlace(currentFrom)
            return
        }

        // Determine best coordinate for start
        let targetCoord: CLLocationCoordinate2D? = {
            if let sc = app.draft.startCoord?.cl { return sc }
            if let first = app.draft.selected?.coords.first?.cl { return first }
            if let loc = LocationService.shared.currentLocation?.coordinate { return loc }
            return nil
        }()

        guard let coord = targetCoord else {
            startPlaceDisplayName = "Current Location"
            return
        }

        let geocoded = await LocationService.shared.reverseGeocode(coordinate: coord)
        let clean = geocoded.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty && !clean.contains("0.0000") {
            let primaryName = clean.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? clean
            if !primaryName.isEmpty {
                startPlaceDisplayName = primaryName
                app.draft.from = primaryName
                return
            }
        }

        if startPlaceDisplayName.isEmpty {
            startPlaceDisplayName = currentFrom.isEmpty ? "Current Location" : currentFrom
        }
    }

    private func shortPlace(_ s: String) -> String {
        s.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? s
    }

    // MARK: - When card

    private var whenCard: some View {
        VStack(spacing: 10) {
            // Row 1: Only Date & Time (full width, spacious, no truncation)
            HStack(spacing: 10) {
                // Date Button
                Button {
                    focused = false
                    tempDate = app.draft.starts
                    showingDatePicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(hex: 0xFF6B00))
                        Text(app.draft.starts.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .cvText(15, .semibold, inter: true)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Time Button
                Button {
                    focused = false
                    tempTime = app.draft.starts
                    showingTimePicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(hex: 0xFF6B00))
                        Text(app.draft.starts.formatted(.dateTime.hour().minute()))
                            .cvText(15, .semibold, inter: true)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            // Row 2: Start now pushed below
            Button {
                focused = false
                withAnimation(.snappy) {
                    app.draft.starts = Date()
                }
            } label: {
                let isNow = abs(app.draft.starts.timeIntervalSinceNow) < 60
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isNow ? CV.ink : Color(hex: 0xFF6B00))
                    Text("Start now")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isNow ? CV.ink : Color.white)
                    Spacer()
                    if isNow {
                        Text("Active")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CV.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.35), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(isNow ? Color(hex: 0xFF6B00) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isNow ? Color(hex: 0xFF6B00) : Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func pillContent(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: 0xFF6B00))
            Text(text).cvText(14, .semibold, inter: true)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Sheets

    private var dateSheet: some View {
        NavigationStack {
            VStack {
                DatePicker("Select Date", selection: $tempDate,
                           in: Calendar.current.startOfDay(for: .now)...,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Color(hex: 0xFF6B00))
                    .padding()
                Spacer()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { apply(date: tempDate); showingDatePicker = false }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFF6B00))
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.height(450)])
    }

    private var timeSheet: some View {
        NavigationStack {
            VStack {
                DatePicker("Select Time", selection: $tempTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding(.top, 20)
                Spacer()
            }
            .navigationTitle("Select Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { apply(time: tempTime); showingTimePicker = false }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xFF6B00))
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.height(280)])
    }

    private func apply(date: Date) {
        let cal = Calendar.current
        let dc = cal.dateComponents([.year, .month, .day], from: date)
        var cur = cal.dateComponents([.year, .month, .day, .hour, .minute], from: app.draft.starts)
        cur.year = dc.year; cur.month = dc.month; cur.day = dc.day
        if let merged = cal.date(from: cur) { app.draft.starts = merged }
    }

    private func apply(time: Date) {
        let cal = Calendar.current
        let tc = cal.dateComponents([.hour, .minute], from: time)
        var cur = cal.dateComponents([.year, .month, .day, .hour, .minute], from: app.draft.starts)
        cur.hour = tc.hour; cur.minute = tc.minute; cur.second = 0
        if var merged = cal.date(from: cur) {
            // If user sets a time earlier than now on the current day, advance to next day
            if merged < Date() && cal.isDateInToday(merged) {
                if let nextDay = cal.date(byAdding: .day, value: 1, to: merged) {
                    merged = nextDay
                }
            }
            app.draft.starts = merged
        }
    }
}
