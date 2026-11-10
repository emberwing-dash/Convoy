// PlanReviewView.swift
import SwiftUI

struct PlanReviewView: View {
    @Environment(AppState.self) private var app
    @FocusState private var focused: Bool
    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @State private var tempDate = Date()
    @State private var tempTime = Date()
    @State private var showNameError = false

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        RoundIconButton(symbol: "chevron.left") { app.pop() }
                        Spacer()
                    }
                    .padding(.top, 4)

                    Text("New ride").cvText(17, .semibold, tracking: -0.204, inter: true)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text("What's the plan?").cvText(32, .bold, tracking: -0.64, inter: true)
                        .padding(.top, 8)
                    Text("Name your ride and set the time.")
                        .cvText(16, color: CV.cream.opacity(0.65), inter: true)

                    FieldLabel(text: "Ride name").padding(.top, 14)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("", text: $app.draft.name,
                                  prompt: Text(app.draft.to.isEmpty
                                               ? "e.g. Morning ride"
                                               : "e.g. Ride to \(app.draft.to.components(separatedBy: ",")[0])")
                                                .foregroundColor(CV.cream.opacity(0.40)))
                            .focused($focused)
                            .tint(CV.red)
                            .cvText(17, .semibold, tracking: -0.102, inter: true)
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .glassRounded(18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(showNameError ? CV.red : Color.clear, lineWidth: 1.5)
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

                    routeMap.padding(.top, 10)
                    RouteSummaryCard(draft: app.draft, numberedStops: false)
                        .padding(.top, 4)

                    FieldLabel(text: "When").padding(.top, 14)
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
            if app.draft.selected == nil &&
               (!app.draft.from.isEmpty || app.draft.startCoord != nil) &&
               (!app.draft.to.isEmpty || app.draft.endCoord != nil) {
                await app.findRoutes()
            }
        }
    }

    // MARK: - Route map (sized to full width, fixed height)

    private var routeMap: some View {
        ZStack(alignment: .topLeading) {
            if let r = app.draft.selected {
                RouteSnapshotView(coords: r.coords, size: CGSize(width: 353, height: 160))
            } else if let sc = app.draft.startCoord, let ec = app.draft.endCoord {
                let waypoints = [sc] + app.draft.stopCoords + [ec]
                RouteSnapshotView(coords: waypoints, size: CGSize(width: 353, height: 160))
            } else {
                Rectangle().fill(Color(hex: 0x101013))
            }
            Text("\(app.draft.distanceText(app.draft.style)) · \(app.draft.durationText(app.draft.style))")
                .cvText(13, .semibold, color: .white, inter: true)
                .padding(.horizontal, 12).frame(height: 30)
                .background(CV.red, in: Capsule())
                .offset(x: 12, y: 12)
            Button { app.popToLast(2) } label: {
                Text("Edit route").cvText(13, .semibold, color: .white, inter: true)
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Capsule())
            }
            .buttonStyle(.plain)
            .offset(x: 256, y: 12)
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
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
            }
            .buttonStyle(.plain)

            Button {
                focused = false
                tempTime = app.draft.starts
                showingTimePicker = true
            } label: {
                pillContent(icon: "clock",
                            text: app.draft.starts.formatted(.dateTime.hour().minute()))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
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
                    .tint(CV.red)
                    .padding()
                Spacer()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { apply(date: tempDate); showingDatePicker = false }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CV.red)
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
                        .foregroundStyle(CV.red)
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
        if let merged = cal.date(from: cur) { app.draft.starts = merged }
    }
}
