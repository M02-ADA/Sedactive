import SwiftUI

struct TrackingRootView: View {
    @StateObject private var controller = TrackingController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TrackingTestView(controller: controller, camera: controller.camera)
            .onAppear { if scenePhase == .active { controller.start() } }
            .onDisappear { controller.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { controller.start() } else { controller.stop() }
            }
            .preferredColorScheme(.light)
    }
}
