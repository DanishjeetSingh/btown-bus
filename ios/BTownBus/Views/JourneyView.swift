import SwiftUI
import MapKit

struct JourneyView: View {
    @Environment(AppStore.self) private var store
    @Environment(TripTracker.self) private var tracker
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var showWalking = false
    @State private var pickupIndex = 0
    @State private var destinationOffset = 1
    @State private var selectedPatternId: String?
    @State private var boardingProblem: String?
    @State private var choosingDestination = false

    var body: some View {
        NavigationStack {
            if let watch = tracker.watch {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let ride = watch.ride {
                            Text(ride.destinationName).font(.title2.bold())
                            Text(tracker.status?.phase == .requestStop ? "Request your stop now" : ride.atDestination ? "Did you get off?" : "\(ride.remainingStops) stops remaining")
                                .font(.headline)
                            if let problem = tracker.rideProblem { Text(problem).foregroundStyle(.orange) }
                            Text("Confirm after you leave the bus. GPS and bus feed updates estimate progress; check your surroundings if updates are unavailable.")
                                .foregroundStyle(.secondary)
                            Button("I got off · End trip") { tracker.stop(); dismiss() }
                                .buttonStyle(.borderedProminent)
                        } else if choosingDestination {
                            if let boardingRoute = tracker.boardingRoute, boardingRoute.patterns.first?.id == selectedPatternId {
                                destinationPicker(watch: watch, route: boardingRoute)
                            } else {
                                Text("The selected bus's direction is unavailable. Wait for a fresh bus update before choosing a destination.")
                                if let problem = boardingProblem { Text(problem).foregroundStyle(.orange) }
                                Button("Back") { choosingDestination = false }
                            }
                        } else {
                            Text(store.stop(watch.stopKey)?.name ?? "Pickup stop").font(.title2.bold())
                            if let pickup = store.stop(watch.stopKey), location.isAtStop(pickup) {
                                Text("You're at the pickup stop.").font(.headline)
                            }
                            Button("Walk to stop") { showWalking = true }.buttonStyle(.borderedProminent)
                            Divider()
                            Button("I'm on board · Choose my stop") {
                                pickupIndex = tracker.boardingRoute?.stopIds.firstIndex(of: watch.stopId) ?? 0
                                destinationOffset = 1
                                selectedPatternId = tracker.boardingRoute?.patterns.first?.id
                                boardingProblem = nil
                                choosingDestination = true
                            }.buttonStyle(.borderedProminent)
                            Text("Confirm only after boarding. Ride mode uses your phone's GPS and checks the selected bus every 15 seconds.")
                                .foregroundStyle(.secondary)
                            Button("I missed this bus · End trip", role: .destructive) { tracker.stop(); dismiss() }
                        }
                    }.padding(20)
                }
                .fullScreenCover(isPresented: $showWalking) {
                    if let stop = store.stop(watch.stopKey) { WalkDirectionsView(stop: stop) }
                }
                .navigationTitle(watch.ride == nil ? "Your journey" : "Ride mode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            } else {
                ContentUnavailableView("No tracked trip", systemImage: "bus")
            }
        }
    }

    @ViewBuilder private func destinationPicker(watch: TripWatch, route: TransitRoute) -> some View {
        let pickups = route.stopIds.indices.filter { route.stopIds[$0] == watch.stopId }
        Text("Where are you getting off?").font(.title2.bold())
        if pickups.count > 1 {
            Text("This route visits your pickup more than once. Choose the visit you boarded at.").foregroundStyle(.secondary)
            Picker("Pickup visit", selection: $pickupIndex) {
                ForEach(pickups, id: \.self) { index in
                    Text("Visit \(index + 1) · next: \(name(route.stopIds.indices.contains(index + 1) ? route.stopIds[index + 1] : watch.stopId, agency: watch.agency))").tag(index)
                }
            }.onChange(of: pickupIndex) { _, _ in destinationOffset = 1 }
        }
        let offsets = Array(1..<max(1, route.patterns.first?.loops == true ? route.stopIds.count : route.stopIds.count - pickupIndex))
        if offsets.isEmpty {
            Text("No later stops are available in the route data. Ride reminders across the end of a route aren't supported yet.")
        } else {
            Picker("Destination", selection: $destinationOffset) {
                ForEach(offsets, id: \.self) { offset in
                    Text("\(offset). \(name(route.stopIds[(pickupIndex + offset) % route.stopIds.count], agency: watch.agency))").tag(offset)
                }
            }.pickerStyle(.wheel)
            Button("Confirm boarding · Start ride mode") {
                if tracker.board(pickupIndex: pickupIndex, destinationIndex: destinationOffset, patternId: selectedPatternId) {
                    choosingDestination = false
                } else {
                    boardingProblem = "The bus data changed. Go back and choose your destination again."
                }
            }.buttonStyle(.borderedProminent)
            Text("You'll be reminded after leaving the stop before your destination. Keep notifications and location enabled.")
                .foregroundStyle(.secondary)
        }
        if let problem = boardingProblem { Text(problem).foregroundStyle(.orange) }
        Button("Back") { choosingDestination = false }
    }

    private func name(_ id: String, agency: Agency) -> String {
        store.stop(TransitKey(agency: agency, id: id))?.name ?? id
    }
}
