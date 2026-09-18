import SwiftUI

@main
struct MatariApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePanelView(viewModel: viewModel)
        } label: {
            MenuBarLabelView(snapshot: viewModel.snapshot, isLoading: viewModel.isScanning)
        }
        .menuBarExtraStyle(.window)

    }
}
