import SwiftUI

struct PrimaryCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            content
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
