import SwiftData
import SwiftUI

@main
struct TaiAssistantApp: App {
    private let config: RuntimeAppConfig
    private let dependencies: AppDependencies
    private let modelContainer: ModelContainer

    init() {
        let config: RuntimeAppConfig
        if StrengthConversationUITestSupport.isEnabled {
            config = .uiTestStrengthConversation
            AIDataProcessingConsentStore.accept()
        } else if ImageDomainUITestSupport.isEnabled {
            config = .uiTestImageDomain
            AIDataProcessingConsentStore.accept()
        } else if ProcessInfo.processInfo.arguments.contains("-UITestStrengthSmoke") {
            config = .uiTestStrengthSmoke
            AIDataProcessingConsentStore.accept()
        } else {
            config = .default
        }
        self.config = config
        let container = AppModelContainerFactory.makeContainer(
            inMemory: config.useInMemoryStore,
            includePreviewSeedData: false,
            ownerID: config.localOwnerID
        )
        if ProcessInfo.processInfo.arguments.contains("-UITestStrengthSmoke") {
            try? PreviewSeedData.seedIfNeeded(in: container, ownerID: config.localOwnerID)
            if ProcessInfo.processInfo.arguments.contains("-UITestStrengthActiveWorkout") {
                try? PreviewSeedData.seedActiveStrengthWorkout(
                    in: container,
                    ownerID: config.localOwnerID,
                    confirmedSets: ProcessInfo.processInfo.arguments.contains("-UITestStrengthConfirmedSets")
                        ? 1
                        : 0
                )
            }
        }
        self.modelContainer = container
        self.dependencies = AppDependencies.live(modelContainer: container, config: config)
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
