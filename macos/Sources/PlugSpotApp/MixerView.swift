import SwiftUI
import PlugSpotCore
import CryptoKit
import Foundation

struct MixerView: View {
    let library: AbletonLibrary
    @State private var snapshot: MixerSnapshot?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var saveMessage: String?
    @State private var recoverySnapshots: [SavedMixerSnapshot] = []
    @State private var isShowingRecoverySnapshot = false

    private var channels: [MixerChannelItem] {
        guard let snapshot else { return [] }
        return snapshot.tracks.enumerated().map { MixerChannelItem(track: $0.element, section: "TRACK", position: $0.offset) }
            + snapshot.returnTracks.enumerated().map { MixerChannelItem(track: $0.element, section: "RETURN", position: $0.offset) }
            + [MixerChannelItem(track: snapshot.masterTrack, section: "MASTER", position: 0)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isShowingRecoverySnapshot ? "Recovery Snapshot" : "Live Mixer (\(snapshot?.tracks.count ?? 0) tracks)")
                    .font(.headline)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Menu {
                    if !recoverySnapshots.isEmpty {
                        Button("Return to Live Mixer") {
                            isShowingRecoverySnapshot = false
                            Task { await refreshAndSave() }
                        }
                        Divider()
                        ForEach(recoverySnapshots) { saved in
                            Button {
                                snapshot = saved.snapshot
                                isShowingRecoverySnapshot = true
                                errorMessage = nil
                                saveMessage = "Saved \(saved.savedAt.formatted(date: .abbreviated, time: .shortened)) · \(saved.fileName)"
                            } label: {
                                Text("\(saved.snapshot.setName.isEmpty ? saved.fileName : saved.snapshot.setName) · \(saved.savedAt.formatted(date: .abbreviated, time: .shortened))")
                            }
                        }
                    } else {
                        Text("No recovery snapshots found")
                    }
                    Button("Reload Snapshot List") { loadRecoverySnapshots() }
                } label: {
                    Label("Snapshots (\(recoverySnapshots.count))", systemImage: "clock.arrow.circlepath")
                }
                .help("View mixer recovery snapshots saved outside Ableton Live")
            }
            .padding(.horizontal, 16)

            if let errorMessage, snapshot == nil {
                VStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Mixer Unavailable").font(.headline)
                    Text(errorMessage).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if channels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Waiting for Ableton Live").font(.headline)
                    Text("Open a Live Set to view its mixer.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(channels) { channel in
                            MixerChannelStrip(track: channel.track, section: channel.section)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
            if let errorMessage, snapshot != nil {
                Text("Mixer refresh failed: \(errorMessage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            if let saveMessage {
                Text(saveMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .task {
            loadRecoverySnapshots()
            await refreshAndSave()
        }
    }

    @MainActor
    private func refreshAndSave() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await library.mixer()
            snapshot = fresh
            isShowingRecoverySnapshot = false
            errorMessage = nil
            do {
                try saveSnapshot(fresh)
                saveMessage = "Recovery snapshot saved outside Ableton Live."
                loadRecoverySnapshots()
            } catch {
                saveMessage = "Could not save recovery snapshot: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = error.localizedDescription
            if let latest = recoverySnapshots.first {
                snapshot = latest.snapshot
                isShowingRecoverySnapshot = true
                saveMessage = "Live is unavailable. Showing the latest saved snapshot from \(latest.savedAt.formatted(date: .abbreviated, time: .shortened))."
            } else {
                saveMessage = "No recovery snapshots are available yet."
            }
        }
    }

    private func loadRecoverySnapshots() {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PlugSpot/MixerSnapshots", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            recoverySnapshots = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        recoverySnapshots = files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let document = try? decoder.decode(MixerSnapshotDocument.self, from: data) else { return nil }
                return SavedMixerSnapshot(url: url, savedAt: document.savedAt, snapshot: document.snapshot)
            }
            .sorted { $0.savedAt > $1.savedAt }
    }

    private func saveSnapshot(_ fresh: MixerSnapshot) throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PlugSpot/MixerSnapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = fresh.setPath.isEmpty ? fresh.setID : fresh.setPath
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let sourceName = fresh.setName.isEmpty ? "Unsaved-Set" : fresh.setName
        let cleanedName = String(sourceName.unicodeScalars.map { scalar in
            CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._ -").contains(scalar)
                ? Character(scalar) : "-"
        }).trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        let safeName = cleanedName.isEmpty ? "Unsaved-Set" : cleanedName
        let url = root.appendingPathComponent("\(safeName)-\(digest.prefix(12)).json")
        let document = MixerSnapshotDocument(savedAt: Date(), snapshot: fresh)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
    }
}

private struct MixerSnapshotDocument: Codable {
    let schemaVersion = 1
    let savedAt: Date
    let snapshot: MixerSnapshot
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version"; case savedAt = "saved_at"; case snapshot }
}

private struct SavedMixerSnapshot: Identifiable {
    let url: URL
    let savedAt: Date
    let snapshot: MixerSnapshot
    var id: String { url.path }
    var fileName: String { url.deletingPathExtension().lastPathComponent }
}

private struct MixerChannelItem: Identifiable {
    let track: MixerTrack
    let section: String
    let position: Int
    var id: String { "\(section)-\(position)" }
}

private struct MixerChannelStrip: View {
    let track: MixerTrack
    let section: String

    private var trackColor: Color {
        guard let color = track.color else { return .accentColor }
        return Color(
            .sRGB,
            red: Double((color >> 16) & 0xFF) / 255,
            green: Double((color >> 8) & 0xFF) / 255,
            blue: Double(color & 0xFF) / 255,
            opacity: 1
        )
    }

    var body: some View {
        VStack(spacing: 9) {
            Text(section)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(track.name.isEmpty ? "Untitled" : track.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 32)
            RoundedRectangle(cornerRadius: 2)
                .fill(trackColor)
                .frame(height: 4)
            HStack(alignment: .bottom, spacing: 10) {
                VStack(spacing: 5) {
                    Text("VOL")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                    GeometryReader { proxy in
                        ZStack(alignment: .bottom) {
                            Capsule().fill(Color.primary.opacity(0.09)).frame(width: 6)
                            Capsule().fill(trackColor.opacity(0.7)).frame(width: 6, height: proxy.size.height * min(max(track.volume ?? 0, 0.05), 1))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(height: 100)
                    Text(track.volume.map { String(format: "%.2f", $0) } ?? "—")
                        .font(.system(size: 9, design: .monospaced))
                }
                VStack(spacing: 5) {
                    Text("PAN")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(trackColor)
                        .frame(width: 38, height: 18)
                        .background {
                            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 2)
                        }
                        .offset(x: CGFloat(min(max(track.pan ?? 0, -1), 1)) * 11)
                    Text(track.pan.map { String(format: "%+.2f", $0) } ?? "—")
                        .font(.system(size: 9, design: .monospaced))
                }
                .frame(height: 126)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                if track.devices.isEmpty {
                    Text("No devices")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(track.devices.enumerated()), id: \.offset) { _, device in
                        Text(device.name)
                            .lineLimit(2)
                            .foregroundStyle(device.className == "PluginDevice" ? .primary : .secondary)
                        ForEach(Array(device.chains.enumerated()), id: \.offset) { _, chain in
                            Text("↳ \(chain.name)")
                                .foregroundStyle(.secondary)
                                .padding(.leading, 6)
                            ForEach(Array(chain.devices.enumerated()), id: \.offset) { _, nested in
                                Text("   \(nested.name)")
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 8)
                            }
                        }
                    }
                }
            }
            .font(.system(size: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(width: 168)
        .frame(minHeight: 300, alignment: .top)
        .background(PlugSpotPalette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PlugSpotPalette.iridescence.opacity(0.24)))
    }
}
