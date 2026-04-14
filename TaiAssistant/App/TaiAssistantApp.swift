import SwiftData
import SwiftUI

@main
struct TaiAssistantApp: App {
    private let config: RuntimeAppConfig
    private let dependencies: AppDependencies
    private let modelContainer: ModelContainer

    init() {
        let config = RuntimeAppConfig.default
        self.config = config
        self.dependencies = AppDependencies.makeDefault(
            useLocalPersistence: false,
            inMemoryStore: config.useInMemoryStore
        )
        self.modelContainer = AppModelContainerFactory.makeContainer(
            inMemory: config.useInMemoryStore,
            includePreviewSeedData: config.useInMemoryStore
        )
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(
                dependencies: dependencies,
                config: config
            )
            .modelContainer(modelContainer)
        }
    }
}
