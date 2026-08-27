import SwiftUI

struct AppSheetHost: View {
    let destination: AppSheet
    let model: AppModel

    var body: some View {
        NavigationStack {
            switch destination {
            case .details:
                CoverageDetailsSheet(model: model)
            #if DEBUG
            case .debugInspector:
                DebugRouteInspectorSheet(model: model)
            #endif
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
