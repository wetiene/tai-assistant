import SwiftData
import SwiftUI

@main
struct TaiAssistantApp: App {
    private let config: AppConfig
    private let dependencies: AppDependencies
    private let modelContainer: ModelContainer

    init() {
        let config = AppConfig.default
        self.config = config
        self.dependencies = AppDependencies.makeDefault()
        self.modelContainer = AppModelContainerFactory.makeContainer(
            inMemory: config.useInMemoryStore
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
