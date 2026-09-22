import SwiftData
import SwiftUI

@main
struct KelimeDefteriApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Self.container)
    }

    private static var container: ModelContainer {
        #if DEBUG
        // Ekran görüntüleri için: `-demo` ile açılınca gerçek defter yerine bellekteki örnekler.
        if ProcessInfo.processInfo.arguments.contains("-demo") { return PreviewData.container }
        #endif
        return SharedStore.container
    }
}
