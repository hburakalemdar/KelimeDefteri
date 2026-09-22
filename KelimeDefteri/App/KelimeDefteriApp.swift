import SwiftData
import SwiftUI

@main
struct KelimeDefteriApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(SharedStore.container)
    }
}
