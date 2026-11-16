// RideEditSheet.swift
// Edit an existing ride: name, start, checkpoints, destination and when.
// Places show search suggestions while typing; picking one closes the list and keeps its exact
// coordinates. If any place changes, Save recalculates the route so the map and distance stay true.
import SwiftUI
import MapKit

struct RideEditSheet: View {
    @Environment(AppState.self) private var app
    let ride: Ride
    var onDismiss: () -> Void

    /// One editable place: what's typed, and the exact point once picked from suggestions.
    struct Place: Equatable {
        var text: String
        var coord: Coord?
    }

    enum Field: Hashable { case name, from, to, stop(Int), newStop }

    @State private var name: String
    @State private var from: Place
    @State private var to: Place
    @State private var stops: [Place]
    @State private var newStop = Place(text: "", coord: nil)
    @State private var date: Date
    @State private var startNow = false

    @FocusState private var focus: Field?
    @State private var suggestions: [MKLocalSearchCompletion] = []
    @State private var suggestFor: Field?
    @State private var searchTask: Task<Void, Never>?
    /// Text set by picking a suggestion — not treated as typing.
    @State private var programmatic: String?
    private let completer = SearchCompleter()

    @State private var saving = false
    @State private var errorText: String?

    init(ride: Ride, onDismiss: @escaping () -> Void) {
        self.ride = ride
        self.onDismiss = onDismiss
        _name = State(initialValue: ride.title)
        _from = State(initialValue: Place(text: ride.plan.from, coord: ride.plan.startCoord))
        _to = State(initialValue: Place(text: ride.plan.to, coord: ride.plan.endCoord))
        let coords = ride.plan.stopCoords
        _stops = State(initialValue: ride.plan.stops.enumerated().map { i, s in
            Place(text: s, coord: i < coords.count ? coords[i] : nil)
        })
        _date = State(initialValue: max(ride.departs, .now))
    }

    private var routeChanged: Bool {
        from.text != ride.plan.from || to.text != ride.plan.to || stops.map(\.text) != ride.plan.stops
            || from.coord != ride.plan.startCoord || to.coord != ride.plan.endCoord
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section("Ride name") {
                        TextField("", text: $name, prompt: Text("Name your ride").foregroundStyle(CV.dim))
                            .focused($focus, equals: .name)
                            .submitLabel(.done)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CV.text)
                            .padding(.horizontal, 16).frame(height: 54)
                            .card()
                    }

                    section("Route") {
                        routeCard
                        if let r = ride.plan.selected, !routeChanged {
                            RouteSnapshotView(coords: r.coords, height: 150, corner: 18)
                                .frame(maxWidth: .infinity)
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(CV.stroke, lineWidth: 1))
                                .padding(.top, 10)
                        } else if routeChanged {
                            Label("The route and distance will be recalculated when you save.", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CV.muted)
                                .padding(.top, 10).padding(.leading, 4)
                        }
                    }

                    section("When") { whenCard }

                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CV.danger)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Tapping empty space closes the keyboard and any suggestions.
            .simultaneousGesture(TapGesture().onEnded { closeKeyboard() })
        }
        .background(CV.bg2.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .interactiveDismissDisabled(saving)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button { onDismiss() } label: {
                Text("Cancel").font(.system(size: 16, weight: .medium)).foregroundStyle(CV.muted)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Edit ride").font(.system(size: 17, weight: .semibold)).foregroundStyle(CV.text)
            Spacer()
            Button { Task { await save() } } label: {
                Group {
                    if saving { ProgressView().tint(CV.onAccent) }
                    else { Text("Save").font(.system(size: 15, weight: .semibold)) }
                }
                .foregroundStyle(CV.onAccent)
                .frame(width: 70, height: 34)
                .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(saving || to.text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    // MARK: Route

    private var routeCard: some View {
        VStack(spacing: 0) {
            placeRow(.from, place: $from, marker: AnyView(dot(CV.route)), label: "Start", placeholder: "Where you set off")
            ForEach(stops.indices, id: \.self) { i in
                divider
                placeRow(.stop(i), place: $stops[i], marker: AnyView(numbered(i + 1)), label: "Checkpoint \(i + 1)",
                         placeholder: "Search a place") {
                    Button {
                        withAnimation(.snappy) { stops.remove(at: i) }
                        if suggestFor == .stop(i) { clearSuggestions() }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(CV.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove checkpoint \(i + 1)")
                }
            }
            divider
            placeRow(.newStop, place: $newStop, marker: AnyView(addMarker), label: "Add a checkpoint",
                     placeholder: "Search a fuel stop, café, viewpoint…")
            divider
            placeRow(.to, place: $to, marker: AnyView(flag), label: "Destination", placeholder: "Where you're headed")
        }
        .card()
    }

    @ViewBuilder
    private func placeRow(_ field: Field, place: Binding<Place>, marker: AnyView, label: String, placeholder: String,
                          @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                marker.frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(CV.dim)
                    TextField("", text: place.text, prompt: Text(placeholder).foregroundStyle(CV.dim))
                        .focused($focus, equals: field)
                        .submitLabel(.done)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CV.text)
                        .onChange(of: place.wrappedValue.text) { _, v in typed(v, in: field, place: place) }
                }
                Spacer(minLength: 4)
                trailing()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 62)

            if suggestFor == field && focus == field && !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.prefix(5).enumerated()), id: \.offset) { i, s in
                        Button { pick(s, for: field, place: place) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 18))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(CV.route)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.text).lineLimit(1)
                                    if !s.subtitle.isEmpty {
                                        Text(s.subtitle).font(.system(size: 12)).foregroundStyle(CV.muted).lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).frame(height: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < min(suggestions.count, 5) - 1 {
                            Rectangle().fill(CV.separator).frame(height: 0.5).padding(.leading, 44)
                        }
                    }
                }
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 10).padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.2), value: suggestions.count)
    }

    private var divider: some View { Rectangle().fill(CV.separator).frame(height: 0.5).padding(.leading, 56) }

    private func dot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 12, height: 12).overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
    }
    private func numbered(_ n: Int) -> some View {
        Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(CV.onAccent)
            .frame(width: 20, height: 20).background(CV.text, in: Circle())
    }
    private var addMarker: some View {
        Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(CV.text)
            .frame(width: 20, height: 20)
            .overlay(Circle().strokeBorder(CV.text.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])))
    }
    private var flag: some View {
        Image(systemName: "flag.checkered").font(.system(size: 11, weight: .bold)).foregroundStyle(CV.onAccent)
            .frame(width: 22, height: 22).background(CV.text, in: Circle())
    }

    // MARK: When

    private var whenCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $startNow.animation(.snappy)) {
                rowLabel("bolt.fill", "Start now")
            }
            .tint(CV.success)
            .padding(.horizontal, 16).frame(height: 56)
            if !startNow {
                divider
                HStack {
                    rowLabel("calendar", "Date")
                    Spacer()
                    DatePicker("", selection: $date, in: Date()..., displayedComponents: .date).labelsHidden()
                }
                .padding(.horizontal, 16).frame(height: 56)
                divider
                HStack {
                    rowLabel("clock", "Time")
                    Spacer()
                    DatePicker("", selection: $date, displayedComponents: .hourAndMinute).labelsHidden()
                }
                .padding(.horizontal, 16).frame(height: 56)
            }
        }
        .card()
    }

    private func rowLabel(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.text)
                .frame(width: 30, height: 30).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(CV.text)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold)).tracking(0.8)
                .foregroundStyle(CV.muted).padding(.leading, 4)
            content()
        }
    }

    // MARK: Suggestions

    private func typed(_ text: String, in field: Field, place: Binding<Place>) {
        if text == programmatic { programmatic = nil; return }
        place.wrappedValue.coord = nil          // typed text no longer matches the old point
        errorText = nil
        searchTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { clearSuggestions(); return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            completer.search(q) { results in
                guard focus == field else { return }   // field closed meanwhile: ignore
                suggestFor = field
                suggestions = results
            }
        }
    }

    private func pick(_ s: MKLocalSearchCompletion, for field: Field, place: Binding<Place>) {
        let full = s.subtitle.isEmpty ? s.title : "\(s.title), \(s.subtitle)"
        searchTask?.cancel()
        clearSuggestions()
        programmatic = full
        place.wrappedValue.text = full
        focus = nil
        Task {
            let req = MKLocalSearch.Request(completion: s)
            let coord = try? await MKLocalSearch(request: req).start().mapItems.first?.placemark.coordinate
            if field == .newStop {
                withAnimation(.snappy) { stops.append(Place(text: full, coord: coord.map(Coord.init))) }
                programmatic = ""
                newStop = Place(text: "", coord: nil)
            } else {
                place.wrappedValue.coord = coord.map(Coord.init)
            }
        }
    }

    private func clearSuggestions() {
        suggestions = []
        suggestFor = nil
    }

    private func closeKeyboard() {
        guard focus != nil else { return }
        focus = nil
        clearSuggestions()
    }

    // MARK: Save

    private func save() async {
        closeKeyboard()
        guard let idx = app.rides.firstIndex(where: { $0.id == ride.id }) else { onDismiss(); return }
        saving = true
        defer { saving = false }

        var updated = app.rides[idx]
        let title = name.trimmingCharacters(in: .whitespaces)
        updated.title = title.isEmpty ? ride.title : title
        let when = startNow ? Date() : date
        updated.departs = when
        updated.displayDate = when.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        updated.displayTime = when.formatted(.dateTime.hour().minute())
        updated.lockText = "Start ride opens \(when.formatted(.dateTime.hour().minute()))"
        updated.plan.starts = when

        if routeChanged {
            let keptStops = stops.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            let stopCoords = keptStops.compactMap(\.coord)
            await app.planner.plan(from: from.text, to: to.text, stops: keptStops.map(\.text),
                                   fromCoord: from.coord?.cl, toCoord: to.coord?.cl,
                                   stopCoords: stopCoords.count == keptStops.count ? stopCoords.map(\.cl) : [])
            guard app.planner.state == .ready else {
                errorText = "Couldn't find a road route for these places. Check the names and try again."
                return
            }
            updated.plan.from = from.text
            updated.plan.to = to.text
            updated.plan.stops = keptStops.map(\.text)
            updated.plan.stopCoords = stopCoords.count == keptStops.count ? stopCoords : []
            updated.plan.routes = app.planner.routes
            updated.plan.startCoord = app.planner.start
            updated.plan.endCoord = app.planner.end
            updated.distance = updated.plan.distanceText(updated.plan.style)
            updated.duration = updated.plan.durationText(updated.plan.style)
            updated.place = to.text.components(separatedBy: ",").first ?? to.text
        }

        app.rides[idx] = updated
        StorageService.shared.saveRide(updated)
        if let userId = app.backendUserId {
            Task { try? await SupabaseManager.shared.updateRide(updated, userId: userId) }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDismiss()
    }
}

private extension View {
    func card() -> some View {
        background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(CV.stroke, lineWidth: 1))
    }
}
