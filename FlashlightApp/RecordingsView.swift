import SwiftUI
import AVKit

struct RecordingsView: View {
    @ObservedObject var cam: CameraManager
    @Environment(\.dismiss) var dismiss
    @State private var playURL: URL?
    @State private var showPlayer = false
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            List {
                if cam.recordings.isEmpty {
                    Text("还没有录像，回到主界面开始录制").foregroundStyle(.gray)
                }
                ForEach(cam.recordings, id: \.self) { url in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent).font(.subheadline).lineLimit(1)
                            HStack(spacing: 12) {
                                if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                                    Text(size > 1048576 ? "\(size/1048576) MB" : "\(size/1024) KB")
                                        .font(.caption).foregroundStyle(.gray)
                                }
                                if let date = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate {
                                    Text(date.formatted(date: .numeric, time: .shortened))
                                        .font(.caption).foregroundStyle(.gray)
                                }
                            }
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Button { playURL = url; showPlayer = true } label: {
                                Image(systemName: "play.circle").font(.title3)
                            }
                            Button { shareURL = url } label: {
                                Image(systemName: "square.and.arrow.up").font(.title3)
                            }
                            Button { cam.delete(url) } label: {
                                Image(systemName: "trash").font(.title3).foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("录像管理")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } }
            }
        }
        .sheet(isPresented: $showPlayer) {
            if let url = playURL { VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea() }
        }
        .sheet(item: $shareURL) { url in
            ActivityView(items: [url])
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_: UIActivityViewController, context: Context) {}
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}
