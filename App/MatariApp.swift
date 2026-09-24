import SwiftUI
import AppKit

@main
struct MatariApp: App {
    @StateObject private var viewModel = UsageViewModel()
    @StateObject private var floatingPanel = FloatingUsagePanel()

    var body: some Scene {
        MenuBarExtra {
            if floatingPanel.isPinned {
                VStack(alignment: .leading, spacing: 12) {
                    Text("MATARI 독립창으로 보는 중").font(.headline)
                    Button("독립창 앞으로 가져오기") { floatingPanel.show() }
                    Button("메뉴바로 돌아가기") { floatingPanel.unpin() }
                }
                .padding(16)
            } else {
                UsagePanelView(viewModel: viewModel) {
                    floatingPanel.pin(viewModel: viewModel)
                }
            }
        } label: {
            MenuBarLabelView(snapshot: viewModel.snapshot, isLoading: viewModel.isScanning)
        }
        .menuBarExtraStyle(.window)

    }
}

@MainActor
final class FloatingUsagePanel: ObservableObject {
    @Published private(set) var isPinned = false
    private var panel: NSPanel?
    private var lastOrigin: NSPoint?

    func pin(viewModel: UsageViewModel) {
        guard panel == nil else { show(); return }
        let menuWindow = NSApp.keyWindow
        let window = UsageFloatingWindow(contentRect: NSRect(x: 0, y: 0, width: 336, height: 600),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "MATARI 사용량"
        window.level = .floating
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let content = UsagePanelView(viewModel: viewModel, isPinned: true) { [weak self] in
            self?.unpin()
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: PanelSizePreference.self, value: geometry.size)
            }
        }
        .onPreferenceChange(PanelSizePreference.self) { [weak self] size in
            self?.resize(to: size)
        }
        let hosting = NSHostingView(rootView: content)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        if let lastOrigin {
            window.setFrameOrigin(lastOrigin)
        } else {
            window.center()
        }
        // A disconnected monitor must not strand the panel offscreen.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) {
            window.center()
        }
        panel = window
        isPinned = true
        menuWindow?.orderOut(nil)
        show()
    }

    func show() {
        panel?.makeKeyAndOrderFront(nil)
    }

    private func resize(to size: CGSize) {
        guard let panel, size.width > 0, size.height > 0,
              panel.contentView?.frame.size != size else { return }
        let top = panel.frame.maxY
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: top - panel.frame.height))
    }

    func unpin() {
        lastOrigin = panel?.frame.origin
        panel?.close()
        panel = nil
        isPinned = false
    }
}

private struct PanelSizePreference: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

private final class UsageFloatingWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) {
        // Escape does not dismiss an explicitly pinned usage panel.
    }
}
