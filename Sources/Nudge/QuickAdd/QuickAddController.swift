import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class QuickAddState {
    var text = ""
    /// Incremented each time the field should take focus.
    var focusRequest = 0
    /// Content height reported by the view; the preview row makes it taller.
    var height: CGFloat = 60
}

/// The Quick Add bar: a single text field on the active display. Enter adds and closes.
@MainActor
final class QuickAddController {
    static let width: CGFloat = 560

    private let model: TaskListModel
    private let state = QuickAddState()
    private var panel: FloatingPanel?
    private var outsideClickMonitor: Any?

    init(model: TaskListModel) {
        self.model = model
        observeChanges { [weak self] in
            guard let self else { return }
            _ = self.state.height
            if let panel = self.panel, panel.isVisible { self.resize(panel) }
        }
    }

    var isVisible: Bool { panel?.isVisible == true }
    var window: NSWindow? { panel }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView?.layoutSubtreeIfNeeded()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        state.focusRequest += 1
        installMonitor()
    }

    /// Closes without adding. The draft is kept for next time; Esc clears it.
    func close() {
        panel?.orderOut(nil)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    #if DEBUG
    func debugSetText(_ text: String) { state.text = text }
    #endif

    private func submit(parsing: Bool) {
        let added = parsing ? model.add(parsing: state.text) : model.add(title: state.text)
        guard added != nil else { return }
        state.text = ""
        close()
    }

    private func cancel() {
        state.text = ""
        close()
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 60),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.onClose = { [weak self] in self?.cancel() }

        let view = QuickAddView(
            state: state,
            model: model,
            onSubmit: { [weak self] in self?.submit(parsing: true) },
            onSubmitLiteral: { [weak self] in self?.submit(parsing: false) },
            onCancel: { [weak self] in self?.cancel() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    /// Upper third of the display with the mouse pointer, like Spotlight.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.active else { return }
        let visible = screen.visibleFrame
        let top = visible.maxY - visible.height * 0.22
        panel.setFrame(NSRect(x: visible.midX - Self.width / 2, y: top - state.height, width: Self.width, height: state.height), display: true)
    }

    /// Grows downward as the preview appears, keeping the text field in place.
    private func resize(_ panel: NSPanel) {
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = state.height
        frame.origin.y = top - state.height
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func installMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }
}

struct QuickAddView: View {
    @Bindable var state: QuickAddState
    let model: TaskListModel
    let onSubmit: () -> Void
    let onSubmitLiteral: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                TextField("What needs to be done?", text: $state.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
                    .onSubmit(onSubmit)
                    .onOptionReturn(onSubmitLiteral)
                    .onCategoryCompletion($state.text, categories: model.categories)
                    .onExitCommand(perform: onCancel)
            }
            .frame(height: 60)
            if model.parse(state.text).hasDetails || CategoryCompletion.suggestion(for: state.text, in: model.categories) != nil {
                ParsePreview(text: state.text, model: model)
                    .padding(.leading, 32)
                    .padding(.bottom, 14)
            }
        }
        .padding(.horizontal, 18)
        .frame(width: QuickAddController.width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { state.height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .onChange(of: state.focusRequest, initial: true) { focused = true }
    }
}
