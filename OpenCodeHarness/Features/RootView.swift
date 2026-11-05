import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences

    var body: some View {
        ZStack {
            AmbientBackground()

            switch model.phase {
            case .idle, .booting:
                BootView()
                    .transition(.opacity)
            case .failed(let message):
                ServerFailureView(message: message)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .ready:
                HarnessView()
                    .transition(.opacity)
            }

            toastLayer
        }
        .animation(Motion.smooth, value: model.phase)
        .task {
            Diagnostics.log("RootView task, phase=\(model.phase)")
            if case .idle = model.phase {
                await model.boot()
            }
        }
        .onAppear {
            Diagnostics.log("RootView appeared")
            scheduleSelfSnapshotIfRequested()
        }
        .sheet(isPresented: $model.showWorkspacePicker) {
            WorkspacePickerView()
                .environmentObject(model)
                .environmentObject(prefs)
        }
        .sheet(isPresented: $model.showCommandPalette) {
            CommandPaletteView()
                .environmentObject(model)
                .environmentObject(prefs)
        }
        .sheet(isPresented: $model.showQuickOpen) {
            QuickOpenView()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showStats) {
            StatsView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 620)
        }
        .sheet(isPresented: $model.showShortcuts) {
            ShortcutsView()
        }
        .sheet(isPresented: $model.showWorktreeSheet) {
            WorktreeSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: formSheetBinding) {
            if let form = model.pendingForms.first {
                FormSheetView(form: form)
                    .environmentObject(model)
            }
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            model.pendingDeleteSession.map { "Delete “\($0.displayTitle)”?" } ?? "Delete session?",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible
        ) {
            if let session = model.pendingDeleteSession {
                Button("Delete Session", role: .destructive) {
                    Task { await model.deleteSession(session) }
                    model.pendingDeleteSession = nil
                }
            }
            Button("Cancel", role: .cancel) {
                model.pendingDeleteSession = nil
            }
        } message: {
            Text("This removes the session and its child sessions. This cannot be undone.")
        }
        .onExitCommand {
            if model.showCommandPalette { model.showCommandPalette = false }
            if model.showQuickOpen { model.showQuickOpen = false }
        }
    }

    private func scheduleSelfSnapshotIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["OC_HARNESS_SNAPSHOT"], !path.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }),
                  let view = window.contentView else { return }
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
                Diagnostics.log("Wrote self snapshot to \(path)")
            }
        }
    }

    private var formSheetBinding: Binding<Bool> {
        Binding(
            get: { !model.pendingForms.isEmpty },
            set: { if !$0 { model.pendingForms = [] } }
        )
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { model.pendingDeleteSession != nil },
            set: { if !$0 { model.pendingDeleteSession = nil } }
        )
    }

    private var toastLayer: some View {
        VStack {
            VStack(spacing: 8) {
                ForEach(model.toasts) { toast in
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92)))
                }
            }
            .padding(.top, 68)
            Spacer()
        }
        .animation(Motion.smooth, value: model.toasts.map(\.id))
        .allowsHitTesting(false)
    }
}

struct HarnessView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    @State private var sidebarWidth: CGFloat = 286

    var body: some View {
        VStack(spacing: 0) {
            TitleBarView()
            ZStack(alignment: .top) {
                HStack(spacing: 0) {
                    SidebarView()
                        .frame(width: sidebarWidth)
                    Rectangle()
                        .fill(Color.ocBorder)
                        .frame(width: 1)
                    VStack(spacing: 0) {
                        if let session = model.selectedSession {
                            ChatHeaderView(session: session)
                            Rectangle().fill(Color.ocBorder).frame(height: 1)
                            ChatView()
                            ComposerView()
                                .padding(.horizontal, 22)
                                .padding(.bottom, 16)
                                .padding(.top, 8)
                            if model.showTerminal {
                                RunnerPanelView()
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        } else {
                            WorkspaceHomeView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.ocCanvas.opacity(0.38))

                    if prefs.showInspector {
                        Rectangle()
                            .fill(Color.ocBorder)
                            .frame(width: 1)
                        InspectorView()
                            .frame(width: 342)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(Motion.smooth, value: prefs.showInspector)
            }
        }
    }
}

struct TitleBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.ocCanvas.opacity(0.42))
            WindowDragArea()
            HStack(spacing: 12) {
                Color.clear.frame(width: 64)
                BrandWordmark()
                Spacer()
                if case .ready = model.phase {
                    connectionPill
                    HStack(spacing: 2) {
                        IconButton(systemImage: "magnifyingglass", help: "Command palette (⌘K)", size: 28) {
                            model.showCommandPalette = true
                        }
                        IconButton(systemImage: "plus.bubble", help: "New session (⌘N)", size: 28) {
                            Task { await model.newSession() }
                        }
                        IconButton(
                            systemImage: "sidebar.right",
                            help: "Toggle inspector (⇧⌘I)",
                            size: 28,
                            tint: prefs.showInspector ? Color.ocAccent : Color.ocTextSecondary
                        ) {
                            withAnimation(Motion.smooth) { prefs.showInspector.toggle() }
                        }
                        IconButton(
                            systemImage: "terminal",
                            help: "Toggle shell (⌘J)",
                            size: 28,
                            tint: model.showTerminal ? Color.ocAccent : Color.ocTextSecondary
                        ) {
                            withAnimation(Motion.smooth) { model.showTerminal.toggle() }
                        }
                        IconButton(systemImage: "gearshape", help: "Settings (⌘,)", size: 28) {
                            openSettings()
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 54)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.ocBorder).frame(height: 1)
        }
    }

    private var connectionPill: some View {
        HStack(spacing: 6) {
            StatusDot(
                color: model.eventConnection == .connected ? .ocSuccess : .ocWarning,
                pulsing: model.eventConnection != .connected
            )
            Text(connectionLabel)
                .font(.ocMono(9.5, weight: .medium))
                .foregroundStyle(Color.ocTextSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color.ocHover)
        )
        .overlay {
            Capsule().strokeBorder(Color.ocBorder, lineWidth: 0.5)
        }
    }

    private var connectionLabel: String {
        switch model.eventConnection {
        case .connected:
            if let version = model.serverInfo?.version { return "LIVE · v\(version)" }
            return "LIVE"
        case .connecting:
            return "CONNECTING"
        case .reconnecting:
            return "RECONNECTING"
        case .stopped:
            return "OFFLINE"
        }
    }
}
