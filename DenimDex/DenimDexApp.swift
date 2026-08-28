import SwiftUI
import SwiftData

@main
struct DenimDexApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([CollectionItem.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
