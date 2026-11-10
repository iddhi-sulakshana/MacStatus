import SwiftUI

enum PopupMetrics {
    static let width: CGFloat = 420
}

/// The stack of cards. Kept separate from the scroll wrapper so it can also be rendered offscreen.
struct PopupContent: View {
    let snapshot: SystemSnapshot
    let history: StatsHistory
    var onRefresh: () -> Void = {}
    var onQuit: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            HeaderView(cpu: snapshot.cpu, energy: snapshot.energy,
                       thermalState: ProcessInfo.processInfo.thermalState,
                       onRefresh: onRefresh, onQuit: onQuit)

            HStack(alignment: .top, spacing: 10) {
                CPUCard(cpu: snapshot.cpu, history: history.cpu)
                GPUCard(gpu: snapshot.gpu, history: history.gpu)
            }
            MemoryCard(memory: snapshot.memory)
            ProcessesCard(topCPU: snapshot.topCPU, topMemory: snapshot.topMemory)
            EnergyCard(energy: snapshot.energy)
            NetworkCard(network: snapshot.network, connection: snapshot.connection,
                        uploadHistory: history.upload, downloadHistory: history.download)
            DisksCard(disks: snapshot.disks)
        }
        .padding(14)
        .frame(width: PopupMetrics.width)
        .foregroundStyle(.white)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// What the popover hosts: the cards, scrollable when the screen is too short to show them all.
struct PopupView: View {
    @ObservedObject var store: StatsStore
    var onQuit: () -> Void

    @State private var contentHeight: CGFloat = 760

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            PopupContent(snapshot: store.snapshot, history: store.history,
                         onRefresh: { store.refresh() }, onQuit: onQuit)
                .background(GeometryReader { Color.clear.preference(key: ContentHeightKey.self, value: $0.size.height) })
        }
        .frame(width: PopupMetrics.width, height: min(contentHeight, maxHeight))
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onPreferenceChange(ContentHeightKey.self) { if $0 > 0 { contentHeight = $0 } }
    }

    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 900) - 40
    }
}
