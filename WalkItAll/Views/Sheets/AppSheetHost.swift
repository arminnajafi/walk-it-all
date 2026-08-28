import SwiftUI

struct AppSheetHost: View {
    let destination: AppSheet
    let model: AppModel

    var body: some View {
        NavigationStack {
            switch destination {
            case .details:
                CoverageDetailsSheet(model: model)
            case .healthAccess:
                HealthAccessHelpSheet(model: model)
            }
        }
    }
}

struct SheetCloseButton: ToolbarContent {
    @Environment(\.dismiss) private var dismiss

    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
        }
    }
}
