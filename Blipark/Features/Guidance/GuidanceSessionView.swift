import MapKit
import SwiftUI

struct GuidanceSessionView: View {
  @Environment(\.appEnvironment) private var environment
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @EnvironmentObject private var pipRuntime: ParkingGuidancePiPRuntime

  @State private var session: ParkingGuidanceSession
  @State private var showsEndConfirmation = false
  @State private var isResumingPiP = false
  @State private var errorMessage: String?
  let onEnded: () -> Void

  init(session: ParkingGuidanceSession, onEnded: @escaping () -> Void) {
    _session = State(initialValue: session)
    self.onEnded = onEnded
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          guidanceMap
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 20))

          currentCandidateCard
          candidateProgress

          if case .externalMaps(let provider) = session.mode {
            externalMapControls(provider)
          }
        }
        .padding()
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("停車引導")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("收起") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("結束", role: .destructive) { showsEndConfirmation = true }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if hasNextCandidate {
          Button {
            Task { await moveToNextCandidate() }
          } label: {
            Label("這裡無法停車，前往下一個候選", systemImage: "arrow.right.circle.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .padding()
          .background(.regularMaterial)
        }
      }
      .confirmationDialog("要結束這次行程嗎？", isPresented: $showsEndConfirmation) {
        Button("結束行程", role: .destructive) {
          Task { await endTrip() }
        }
        Button("繼續引導", role: .cancel) {}
      } message: {
        Text("結束後會清除進行中的引導，但已儲存的計畫仍會保留。")
      }
      .alert("無法繼續引導", isPresented: errorBinding) {
        Button("好") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "未知錯誤")
      }
    }
  }

  private func externalMapControls(_ provider: ExternalMapProvider) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(
        pipRuntime.isActive ? "PiP 引導顯示中" : "PiP 引導目前已關閉",
        systemImage: pipRuntime.isActive ? "pip.fill" : "pip.remove"
      )
      .font(.headline)
      .foregroundStyle(pipRuntime.isActive ? Color.green : Color.orange)

      if !pipRuntime.isActive {
        PiPPreviewView(displayLayer: pipRuntime.previewDisplayLayer)
          .frame(maxWidth: .infinity)
          .frame(height: pipRuntime.previewAspectRatio >= 4 ? 64 : 180)
          .background(.black)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .accessibilityLabel("PiP 內容預覽")

        Text(pipRuntime.diagnosticMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Button {
        if pipRuntime.isActive {
          openExternalMap(provider)
        } else {
          Task { await resumePiPAndOpenMap(provider) }
        }
      } label: {
        if isResumingPiP {
          ProgressView().frame(maxWidth: .infinity)
        } else {
          Label(
            pipRuntime.isActive
              ? "返回 \(provider.title)"
              : "重新開啟 PiP 並返回 \(provider.title)",
            systemImage: pipRuntime.isActive ? provider.symbolName : "pip.enter"
          )
          .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(isResumingPiP)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .bliparkCard()
  }

  private var guidanceMap: some View {
    Map(initialPosition: .region(mapRegion)) {
      Marker(
        session.destination.name,
        systemImage: "flag.fill",
        coordinate: session.destination.coordinate.clLocationCoordinate
      )
      .tint(.red)

      ForEach(Array(session.orderedCandidates.enumerated()), id: \.element.id) { index, candidate in
        Annotation(candidate.name, coordinate: candidate.coordinate.clLocationCoordinate) {
          Text("\(index + 1)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: index == session.currentCandidateIndex ? 36 : 28,
                   height: index == session.currentCandidateIndex ? 36 : 28)
            .background(
              index == session.currentCandidateIndex ? BliparkStyle.brand : Color.secondary,
              in: Circle()
            )
            .overlay { Circle().stroke(.white, lineWidth: 2) }
        }
      }
    }
    .mapStyle(.standard(elevation: .realistic))
    .mapControls {
      MapCompass()
      MapScaleView()
    }
  }

  private var currentCandidateCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("目前候選").font(.caption).foregroundStyle(.secondary)
      if let candidate = session.currentCandidate {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: candidate.type.symbolName)
            .font(.title2)
            .foregroundStyle(BliparkStyle.brand)
          VStack(alignment: .leading, spacing: 4) {
            Text(candidate.name).font(.title3.bold())
            Text("\(candidate.type.title)・\(candidate.charge.title)")
              .font(.subheadline).foregroundStyle(.secondary)
            Text(distanceText(candidate.coordinate))
              .font(.subheadline).foregroundStyle(.secondary)
          }
        }
      } else {
        Text("沒有可用的停車候選").foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .bliparkCard()
  }

  private var candidateProgress: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("候選順序").font(.headline)
      ForEach(Array(session.orderedCandidates.enumerated()), id: \.element.id) { index, candidate in
        HStack {
          Image(systemName: index == session.currentCandidateIndex ? "location.circle.fill" : "\(index + 1).circle")
            .foregroundStyle(index == session.currentCandidateIndex ? BliparkStyle.brand : .secondary)
          Text(candidate.name)
          Spacer()
          if index < session.currentCandidateIndex {
            Text("已略過").font(.caption).foregroundStyle(.secondary)
          } else if index == session.currentCandidateIndex {
            Text("目前").font(.caption.bold()).foregroundStyle(BliparkStyle.brand)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .bliparkCard()
  }

  private var hasNextCandidate: Bool {
    session.currentCandidateIndex + 1 < session.orderedCandidates.count
  }

  private var mapRegion: MKCoordinateRegion {
    let coordinates = [session.destination.coordinate] + session.orderedCandidates.map(\.coordinate)
    let minLatitude = coordinates.map(\.latitude).min() ?? session.destination.coordinate.latitude
    let maxLatitude = coordinates.map(\.latitude).max() ?? session.destination.coordinate.latitude
    let minLongitude = coordinates.map(\.longitude).min() ?? session.destination.coordinate.longitude
    let maxLongitude = coordinates.map(\.longitude).max() ?? session.destination.coordinate.longitude
    return MKCoordinateRegion(
      center: CLLocationCoordinate2D(
        latitude: (minLatitude + maxLatitude) / 2,
        longitude: (minLongitude + maxLongitude) / 2
      ),
      span: MKCoordinateSpan(
        latitudeDelta: max((maxLatitude - minLatitude) * 1.6, 0.008),
        longitudeDelta: max((maxLongitude - minLongitude) * 1.6, 0.008)
      )
    )
  }

  private func distanceText(_ coordinate: GeoCoordinate) -> String {
    let distance = session.destination.coordinate.straightLineDistance(to: coordinate)
    return distance >= 1_000
      ? String(format: "距目的地直線約 %.1f km", distance / 1_000)
      : "距目的地直線約 \(Int(distance.rounded())) m"
  }

  @MainActor
  private func moveToNextCandidate() async {
    guard hasNextCandidate else { return }
    session.currentCandidateIndex += 1
    session.updatedAt = .now
    do {
      try await environment.guidanceSessions.save(session)
    } catch {
      session.currentCandidateIndex -= 1
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func endTrip() async {
    do {
      pipRuntime.stop()
      try await environment.guidanceSessions.clearActiveSession()
      onEnded()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func openExternalMap(_ provider: ExternalMapProvider) {
    guard let url = GuidanceSessionLaunch.externalMapURL(
      provider: provider,
      destination: session.destination
    ) else { return }
    openURL(url)
  }

  @MainActor
  private func resumePiPAndOpenMap(_ provider: ExternalMapProvider) async {
    isResumingPiP = true
    defer { isResumingPiP = false }

    do {
      async let settings = environment.developerSettings.settings()
      async let preferences = environment.preferences.preferences()
      try await pipRuntime.resume(
        session: session,
        settings: settings,
        triggerDistanceMeters: preferences.guidanceTriggerDistanceMeters
      )
      openExternalMap(provider)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }
}
