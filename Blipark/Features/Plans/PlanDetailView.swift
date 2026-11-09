import MapKit
import SwiftUI

struct PlanDetailView: View {
  @Environment(\.appEnvironment) private var environment
  @State private var plan: ParkingPlan
  @State private var showsEditor = false
  @State private var showsDepartureConfirmation = false
  @State private var presentedSession: ParkingGuidanceSession?

  init(plan: ParkingPlan) {
    _plan = State(initialValue: plan)
  }

  var body: some View {
    List {
      planMap
        .frame(height: 260)
        .listRowInsets(EdgeInsets())

      Section("計畫") {
        LabeledContent("目的地", value: plan.destination.name)
        LabeledContent("車種", value: plan.vehicleType.title)
        if let departure = plan.scheduledDepartureAt {
          LabeledContent(
            "預計出發",
            value: departure.formatted(date: .abbreviated, time: .shortened)
          )
        }
      }

      Section("停車策略") {
        Text(plan.strategy.conciseSummary)
        Label(
          plan.usesGlobalStrategy ? "沿用建立時的 App 預設" : "此計畫的專屬設定",
          systemImage: plan.usesGlobalStrategy ? "arrow.triangle.branch" : "slider.horizontal.3"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Section("候選順序") {
        ForEach(Array(plan.candidates.enumerated()), id: \.element.id) { index, candidate in
          HStack(spacing: 12) {
            Text("\(index + 1)")
              .font(.caption.bold()).foregroundStyle(.white)
              .frame(width: 25, height: 25)
              .background(BliparkStyle.brand, in: Circle())
            VStack(alignment: .leading) {
              Text(candidate.name)
              Text("\(candidate.type.title)・\(candidate.charge.title)")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }

    }
    .navigationTitle(plan.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) { Button("編輯") { showsEditor = true } }
    }
    .sheet(isPresented: $showsEditor) {
      PlanComposerView(
        destination: plan.destination,
        knownLocations: plan.candidates.map(\.parkingLocation),
        existingPlan: plan,
        parkingProvider: environment.parkingData,
        preferencesRepository: environment.preferences,
        planRepository: environment.plans
      ) { updated in
        plan = updated
      }
    }
    .sheet(isPresented: $showsDepartureConfirmation) {
      DepartureConfirmationView(plan: plan) { session in
        presentedSession = session
      }
    }
    .fullScreenCover(item: $presentedSession) { session in
      GuidanceSessionView(session: session) {
        presentedSession = nil
      }
    }
    .safeAreaInset(edge: .bottom) {
      Button {
        showsDepartureConfirmation = true
      } label: {
        Label("開始這個行程", systemImage: "play.circle.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(plan.candidates.isEmpty)
      .padding()
      .background(.regularMaterial)
    }
  }

  private var planMap: some View {
    let coordinates = [plan.destination.coordinate] + plan.candidates.map(\.coordinate)
    return Map(initialPosition: .region(mapRegion(coordinates))) {
      Marker(
        plan.destination.name,
        systemImage: "flag.fill",
        coordinate: plan.destination.coordinate.clLocationCoordinate
      )
      .tint(.red)
      ForEach(Array(plan.candidates.enumerated()), id: \.element.id) { index, candidate in
        Annotation("\(index + 1). \(candidate.name)", coordinate: candidate.coordinate.clLocationCoordinate) {
          Text("\(index + 1)")
            .font(.caption.bold()).foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(BliparkStyle.brand, in: Circle())
        }
      }
    }
  }

  private func mapRegion(_ coordinates: [GeoCoordinate]) -> MKCoordinateRegion {
    let minLatitude = coordinates.map(\.latitude).min() ?? plan.destination.coordinate.latitude
    let maxLatitude = coordinates.map(\.latitude).max() ?? plan.destination.coordinate.latitude
    let minLongitude = coordinates.map(\.longitude).min() ?? plan.destination.coordinate.longitude
    let maxLongitude = coordinates.map(\.longitude).max() ?? plan.destination.coordinate.longitude
    return MKCoordinateRegion(
      center: CLLocationCoordinate2D(
        latitude: (minLatitude + maxLatitude) / 2,
        longitude: (minLongitude + maxLongitude) / 2
      ),
      span: MKCoordinateSpan(
        latitudeDelta: max((maxLatitude - minLatitude) * 1.5, 0.008),
        longitudeDelta: max((maxLongitude - minLongitude) * 1.5, 0.008)
      )
    )
  }
}

