import SwiftData
import SwiftUI

@main
struct KelimeDefteriApp: App {
    var body: some Scene {
        WindowGroup {
            StoreGate(result: Self.store) {
                ContentView()
            }
        }
    }

    private static var store: Result<ModelContainer, Error> {
        #if DEBUG
        // Ekran görüntüleri için: `-demo` ile açılınca gerçek defter yerine bellekteki örnekler.
        if ProcessInfo.processInfo.arguments.contains("-demo") { return .success(PreviewData.container) }
        #endif
        return SharedStore.result
    }
}
