import Testing
@testable import Sedactive

struct TestTargetSmokeTests {
    @Test("The test target can import the app module")
    func appModuleIsAvailable() {
        #expect(String(describing: ContentView.self) == "ContentView")
    }
}
