import DriveCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = ScanModel()
    @State private var isChoosingFolder = false

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle:
                welcome
            case .scanning(let url):
                ProgressView("Scanning \(url.path)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done:
                if let result = model.result {
                    let _ = model.revision
                    PathBar(model: model)
                    Divider()
                    if let batch = model.lastTrash {
                        TrashBanner(model: model, batch: batch)
                        Divider()
                    }
                    HSplitView {
                        TreeView(model: model)
                            .frame(minWidth: 340, idealWidth: 460)
                        SunburstView(model: model)
                            .frame(minWidth: 360)
                        if !model.selection.isEmpty {
                            SelectedTray(model: model)
                                .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
                        }
                    }
                    Divider()
                    DiskBar(result: result)
                        .padding(12)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItemGroup {
                Button(action: scanDisk) {
                    Label("Scan Disk", systemImage: "internaldrive")
                }
                Button { isChoosingFolder = true } label: {
                    Label("Scan Folder…", systemImage: "folder")
                }
                Button {
                    model.reveal(model.selectedItems)
                } label: {
                    Label("Reveal in Finder", systemImage: "magnifyingglass")
                }
                .disabled(model.selection.isEmpty)
            }
        }
        .disabled(model.isScanning)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.scan(url)
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "internaldrive")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("See what takes space on your disk")
                .font(.title2)
            HStack {
                Button("Scan Macintosh HD", action: scanDisk)
                    .keyboardShortcut(.defaultAction)
                Button("Scan a Folder…") { isChoosingFolder = true }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scanDisk() {
        model.scan(URL(fileURLWithPath: "/"))
    }
}
