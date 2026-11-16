// PlanDetailsView.swift
import SwiftUI
import MapKit

struct PlanDetailsView: View {
    @Environment(AppState.self) private var app
    @FocusState private var focused: Bool

    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @State private var tempDate = Date()
    @State private var tempTime = Date()

    var body: some View {
        @Bindable var app = app
        let canContinue = app.draft.routeSet

        DesignCanvas(background: ContourBackdrop()) {
            RoundIconButton(symbol: "chevron.left") { app.pop() }.at(20, 58)
            Text("What’s the plan?").cvText(32, .bold, tracking: -0.64, inter: true).at(20, 118)
            Text("Name your ride, set the route and pick a start time.")
                .cvText(16, color: CV.cream.opacity(0.65), inter: true).at(20, 160)

            FieldLabel(text: "Ride name").at(20, 203)
            TextField("", text: $app.draft.name,
                      prompt: Text("e.g. Morning ride to Coorg").foregroundColor(CV.cream.opacity(0.4)))
                .focused($focused).tint(CV.red)
                .cvText(17, .regular, tracking: -0.102, inter: true)
                .padding(.horizontal, 21).frame(width: 353, height: 56)
                .glassRounded(18).at(20, 226)

            FieldLabel(text: "Route").at(20, 303)
            mapCard.at(20, 326)

            FieldLabel(text: "When").at(20, 576)
            whenCard.at(20, 599)

            PrimaryButton(title: "Initiate plan") {
                guard canContinue else { return }
                // Auto-generate a name if the rider left it blank (#5b)
                if app.draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    app.draft.name = app.draft.effectiveName
                }
                app.push(.planReview)
            }
            .opacity(canContinue ? 1 : 0.3)
            .disabled(!canContinue)
            .frame(width: 353).at(20, 750)
        }
        .sheet(isPresented: $showingDatePicker) { dateSheet }
        .sheet(isPresented: $showingTimePicker) { timeSheet }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onTapGesture { focused = false }
        .task {
            if app.draft.selected == nil
                && (!app.draft.from.isEmpty || app.draft.startCoord != nil)
                && (!app.draft.to.isEmpty || app.draft.endCoord != nil) {
                await app.findRoutes()
            }
        }
    }

    // MARK: - Map card (height reduced to fit When card)

    private var mapCard: some View {
        Button { focused = false; app.push(.planMap) } label: {
            ZStack(alignment: .topLeading) {
                if let r = app.draft.selected {
                    RouteSnapshotView(coords: r.coords, size: CGSize(width: 353, height: 220))
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(app.draft.from.components(separatedBy: ",")[0]) → \(app.draft.to.components(separatedBy: ",")[0])")
                                .cvText(15, .semibold, inter: true).lineLimit(1)
                            Text("\(app.draft.distanceText(app.draft.style)) · \(app.draft.durationText(app.draft.style)) · \(app.draft.style.rawValue)")
                                .cvText(12, color: CV.cream.opacity(0.55), inter: true)
                        }
                        Spacer()
                        Text("Change").cvText(13, .semibold, inter: true)
                            .padding(.horizontal, 14).frame(height: 32)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .padding(.horizontal, 16).frame(width: 321, height: 64)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .offset(x: 16, y: 16)
                } else if let sc = app.draft.startCoord, let ec = app.draft.endCoord {
                    let waypoints = [sc] + app.draft.stopCoords + [ec]
                    RouteSnapshotView(coords: waypoints, size: CGSize(width: 353, height: 220))
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(app.draft.from.components(separatedBy: ",")[0]) → \(app.draft.to.components(separatedBy: ",")[0])")
                                .cvText(15, .semibold, inter: true).lineLimit(1)
                            Text("Setting route…")
                                .cvText(12, color: CV.cream.opacity(0.55), inter: true)
                        }
                        Spacer()
                        Text("Change").cvText(13, .semibold, inter: true)
                            .padding(.horizontal, 14).frame(height: 32)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .padding(.horizontal, 16).frame(width: 321, height: 64)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .offset(x: 16, y: 16)
                } else {
                    Map(initialPosition: .userLocation(fallback: .automatic)) { UserAnnotation() }
                        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                        .frame(width: 353, height: 220)
                        .allowsHitTesting(false)

                    HStack(spacing: 12) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 17, weight: .medium))
                        Text("Set your route").cvText(16, .semibold, inter: true)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CV.cream.opacity(0.5))
                    }
                    .foregroundStyle(CV.cream)
                    .padding(.horizontal, 20).frame(width: 321, height: 52)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .offset(x: 16, y: 152)
                }
            }
            .frame(width: 353, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // MARK: - When card

    private var whenCard: some View {
        HStack(spacing: 8) {
            Text("Starts").cvText(16, .medium, inter: true).padding(.leading, 16)
            Spacer()
            Button {
                focused = false
                tempDate = app.draft.starts
                showingDatePicker = true
            } label: {
                pillContent(icon: "calendar",
                            text: app.draft.starts.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            }.buttonStyle(.plain)

            Button {
                focused = false
                tempTime = app.draft.starts
                showingTimePicker = true
            } label: {
                pillContent(icon: "clock",
                            text: app.draft.starts.formatted(.dateTime.hour().minute()))
            }.buttonStyle(.plain).padding(.trailing, 12)
        }
        .frame(width: 353, height: 60)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func pillContent(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CV.red)
            Text(text).cvText(14, .semibold, inter: true)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var dateSheet: some View {
        NavigationStack {
            VStack {
                DatePicker("Select Date", selection: $tempDate,
                           in: Calendar.current.startOfDay(for: .now)...,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical).tint(CV.red).padding()
                Spacer()
            }
            .navigationTitle("Select Date").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { apply(date: tempDate); showingDatePicker = false }
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(CV.red)
                }
            }.preferredColorScheme(.dark)
        }.presentationDetents([.height(450)])
    }

    private var timeSheet: some View {
        NavigationStack {
            VStack {
                DatePicker("Select Time", selection: $tempTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel).labelsHidden().padding(.top, 20)
                Spacer()
            }
            .navigationTitle("Select Time").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { apply(time: tempTime); showingTimePicker = false }
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(CV.red)
                }
            }.preferredColorScheme(.dark)
        }.presentationDetents([.height(280)])
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
        if let merged = cal.date(from: cur) { app.draft.starts = merged }
    }
}
