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
        let container = AppModelContainerFactory.makeContainer(
            inMemory: config.useInMemoryStore,
            includePreviewSeedData: config.useInMemoryStore,
            ownerID: config.localOwnerID
        )
        self.modelContainer = container
        self.dependencies = AppDependencies.live(modelContainer: container)
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
