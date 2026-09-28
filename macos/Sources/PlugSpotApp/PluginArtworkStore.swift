import AppKit
import Combine
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import PlugSpotCore
import UniformTypeIdentifiers

@MainActor
final class PluginArtworkStore: ObservableObject {
    private static let screenRecordingRequestKey = "BubblePlugScreenRecordingPermissionRequested"
    var willRequestScreenRecordingPermission: (() -> Void)?
    var didRequestScreenRecordingPermission: ((Bool) -> Void)?
    @Published private(set) var pluginImages: [String: NSImage] = [:]
    @Published private(set) var vendorImages: [String: NSImage] = [:]
    @Published private(set) var preparationProgress: Double = 1
    @Published private(set) var isPreparing = false
    @Published private(set) var isCapturingFirstRunImages = false
    @Published private(set) var captureProgress: Double = 0
    @Published private(set) var captureCurrentPlugin = ""
    @Published private(set) var captureStatus = ""
    @Published private(set) var missingPluginImageCount = 0
    @Published private(set) var artworkRevision = 0

    private var requestedPlugins: Set<String> = []
    private var requestedVendors: Set<String> = []
    private var pluginImageOrder: [String] = []
    private var vendorImageOrder: [String] = []
    private var manifest = ArtworkManifest()
    private var preparationKey = ""
    private var requiresArtworkDiscovery = false
    private var currentLiveVersion = ""
    private var preparationTask: Task<ArtworkManifest, Never>?
    private var capturingPlugins: Set<String> = []
    private var firstRunCaptureTask: Task<Void, Never>?

    func hasPluginImage(_ id: String) -> Bool { manifest.plugins[id] != nil }
    func hasVendorImage(_ vendor: String) -> Bool { manifest.vendors[Self.normalized(vendor)] != nil }

    @discardableResult
    func setCustomImage(_ source: URL, pluginID: String? = nil, vendor: String? = nil) -> Bool {
        let role = pluginID == nil ? "vendor" : "plugin"
        guard let permanent = PluginArtworkExtractor.copyCustomImage(source),
              let imagePath = PluginArtworkExtractor.cachedImagePath(at: permanent, role: role) else { return false }
        var overrides = PluginArtworkExtractor.loadOverrides()
        if let pluginID {
            let wasMissing = manifest.plugins[pluginID] == nil
            overrides.plugins[pluginID] = permanent.path
            manifest.plugins[pluginID] = imagePath
            if wasMissing { missingPluginImageCount = max(0, missingPluginImageCount - 1) }
            requestedPlugins.remove(pluginID)
            pluginImages.removeValue(forKey: pluginID)
        } else if let vendor {
            let key = Self.normalized(vendor)
            overrides.vendors[key] = permanent.path
            manifest.vendors[key] = imagePath
            requestedVendors.remove(key)
            vendorImages.removeValue(forKey: key)
        } else { return false }
        PluginArtworkExtractor.saveOverrides(overrides)
        PluginArtworkExtractor.saveManifest(manifest)
        artworkRevision += 1
        return true
    }

    func prepare(
        plugins: [(id: String, item: PluginItem)],
        liveVersion: String,
        force: Bool = false,
        using library: AbletonLibrary? = nil,
        cachedOnly: Bool = false,
        autoCapture: Bool = true
    ) {
        let key = PluginArtworkExtractor.catalogKey(plugins: plugins, liveVersion: liveVersion)
        guard key != preparationKey || force else { return }
        preparationTask?.cancel()
        preparationTask = nil
        preparationKey = key
        currentLiveVersion = liveVersion
        requestedPlugins.removeAll()
        requestedVendors.removeAll()
        pluginImageOrder.removeAll()
        vendorImageOrder.removeAll()
        pluginImages.removeAll()
        vendorImages.removeAll()
        if !force, let saved = PluginArtworkExtractor.loadManifest() {
            let pluginIDs = Set(plugins.map(\.id))
            let vendorKeys = Set(plugins.compactMap { $0.item.vendor }.map(PluginArtworkStore.normalized))
            if saved.key == key {
                manifest = saved
                requiresArtworkDiscovery = false
                missingPluginImageCount = plugins.filter { saved.plugins[$0.id] == nil }.count
                isPreparing = false
                preparationProgress = 1
                if autoCapture, let library { startFirstRunImageCapture(plugins: plugins, library: library) }
                return
            }
            if cachedOnly {
                manifest = ArtworkManifest(
                    key: key,
                    plugins: saved.plugins.filter { pluginIDs.contains($0.key) },
                    vendors: saved.vendors.filter { vendorKeys.contains($0.key) }
                )
                requiresArtworkDiscovery = true
                missingPluginImageCount = plugins.filter { manifest.plugins[$0.id] == nil }.count
                isPreparing = false
                preparationProgress = 1
                return
            }
        }
        if cachedOnly {
            manifest = ArtworkManifest(key: key)
            requiresArtworkDiscovery = true
            missingPluginImageCount = plugins.count
            isPreparing = false
            preparationProgress = 1
            return
        }
        isPreparing = true
        requiresArtworkDiscovery = true
        preparationProgress = 0
        let worker = Task.detached(priority: .utility) {
            PluginArtworkExtractor.prepare(plugins: plugins, liveVersion: liveVersion, key: key) { progress in
                Task { @MainActor in
                    if self.preparationKey == key { self.preparationProgress = progress }
                }
            }
        }
        preparationTask = worker
        Task {
            let completed = await worker.value
            guard preparationKey == key else { return }
            preparationTask = nil
            manifest = completed
            requiresArtworkDiscovery = false
            missingPluginImageCount = plugins.filter { completed.plugins[$0.id] == nil }.count
            isPreparing = false
            preparationProgress = 1
            if autoCapture, let library { startFirstRunImageCapture(plugins: plugins, library: library) }
        }
    }

    func retryFirstRunImageCapture(plugins: [(id: String, item: PluginItem)], library: AbletonLibrary) {
        guard !isPreparing, !isCapturingFirstRunImages else { return }
        startFirstRunImageCapture(plugins: plugins, library: library)
    }

    func loadMissingPluginImages(plugins: [(id: String, item: PluginItem)], liveVersion: String, library: AbletonLibrary) {
        guard !isPreparing, !isCapturingFirstRunImages else { return }
        if requiresArtworkDiscovery {
            prepare(plugins: plugins, liveVersion: liveVersion, force: true, using: library, autoCapture: true)
        } else {
            retryFirstRunImageCapture(plugins: plugins, library: library)
        }
    }

    func cancelFirstRunImageCapture() {
        firstRunCaptureTask?.cancel()
    }

    private func startFirstRunImageCapture(plugins: [(id: String, item: PluginItem)], library: AbletonLibrary) {
        guard !isCapturingFirstRunImages, firstRunCaptureTask == nil else { return }
        let missing = plugins.filter { manifest.plugins[$0.id] == nil }
        guard !missing.isEmpty else {
            missingPluginImageCount = 0
            captureStatus = "All plugin images are ready."
            return
        }
        isCapturingFirstRunImages = true
        captureProgress = 0
        captureCurrentPlugin = ""
        captureStatus = "Starting the VST3 image helper…"
        firstRunCaptureTask = Task { [weak self] in
            guard let self else { return }
            await self.runFirstRunImageCapture(missing, library: library)
        }
    }

    private func runFirstRunImageCapture(
        _ plugins: [(id: String, item: PluginItem)],
        library: AbletonLibrary
    ) async {
        if CGPreflightScreenCaptureAccess() {
            didRequestScreenRecordingPermission?(true)
        } else if !UserDefaults.standard.bool(forKey: Self.screenRecordingRequestKey) {
            UserDefaults.standard.set(true, forKey: Self.screenRecordingRequestKey)
            willRequestScreenRecordingPermission?()
            _ = CGRequestScreenCaptureAccess()
            let isAuthorized = CGPreflightScreenCaptureAccess()
            didRequestScreenRecordingPermission?(isAuthorized)
        }
        guard CGPreflightScreenCaptureAccess() else {
            captureStatus = "Screen Recording permission is required to photograph plugin editors. Enable BubblePlug in System Settings, relaunch it, then retry."
            PluginArtworkExtractor.appendCaptureLog("Screen Recording permission unavailable")
            isCapturingFirstRunImages = false
            firstRunCaptureTask = nil
            return
        }
        let runID = ISO8601DateFormatter().string(from: Date())
        PluginArtworkExtractor.appendCaptureLog("RUN_START id=\(runID) plugins=\(plugins.count) minimumWait=\(HostedVST3ArtworkCapture.minimumWaitSeconds)s timeout=\(HostedVST3ArtworkCapture.timeoutSeconds)s")
        var capturedCount = 0
        var failedCount = 0
        var rejectedWindowCount = 0
        var exceededMinimumWaitCount = 0
        let runStartedAt = Date()
        for (index, entry) in plugins.enumerated() {
            if Task.isCancelled { break }
            captureCurrentPlugin = entry.item.name
            captureStatus = "Capturing \(index + 1) of \(plugins.count) plugin editors outside Live…"
            let item = entry.item
            let liveVersion = currentLiveVersion
            let startedAt = Date()
            do {
                let result = try await Task.detached(priority: .utility) {
                    try HostedVST3ArtworkCapture.capture(plugin: item, liveVersion: liveVersion)
                }.value
                rejectedWindowCount += result.rejectedWindows
                if result.firstVisibleSeconds > HostedVST3ArtworkCapture.minimumWaitSeconds {
                    exceededMinimumWaitCount += 1
                }
                if let url = PluginArtworkExtractor.cacheCapturedImage(result.image, pluginID: entry.id) {
                    manifest.plugins[entry.id] = url.path
                    PluginArtworkExtractor.saveManifest(manifest)
                    missingPluginImageCount = max(0, missingPluginImageCount - 1)
                    artworkRevision += 1
                    capturedCount += 1
                    PluginArtworkExtractor.appendCaptureLog("OK \(entry.item.name) elapsed=\(String(format: "%.2f", Date().timeIntervalSince(startedAt)))s firstVisible=\(String(format: "%.2f", result.firstVisibleSeconds))s rejectedWindows=\(result.rejectedWindows) id=\(runID)")
                } else {
                    failedCount += 1
                    PluginArtworkExtractor.appendCaptureLog("FAIL \(entry.item.name) elapsed=\(String(format: "%.2f", Date().timeIntervalSince(startedAt)))s id=\(runID): could not cache image")
                }
            } catch {
                failedCount += 1
                captureStatus = "Skipped \(entry.item.name): \(error.localizedDescription)"
                PluginArtworkExtractor.appendCaptureLog("FAIL \(entry.item.name) elapsed=\(String(format: "%.2f", Date().timeIntervalSince(startedAt)))s id=\(runID): \(error.localizedDescription)")
            }
            captureProgress = Double(index + 1) / Double(plugins.count)
        }
        firstRunCaptureTask = nil
        PluginArtworkExtractor.appendCaptureLog("RUN_END id=\(runID) captured=\(capturedCount) failed=\(failedCount) rejectedWindows=\(rejectedWindowCount) firstVisibleAfterMinimumWait=\(exceededMinimumWaitCount) elapsed=\(String(format: "%.1f", Date().timeIntervalSince(runStartedAt)))s remaining=\(missingPluginImageCount)")
        isCapturingFirstRunImages = false
        captureCurrentPlugin = ""
        if Task.isCancelled {
            captureStatus = "Image capture paused. Completed images are saved; retry to continue."
        } else if missingPluginImageCount == 0 {
            captureStatus = "All plugin images are ready."
        } else if captureStatus.isEmpty || captureStatus.hasPrefix("Capturing") || captureStatus.hasPrefix("Skipped") {
            captureStatus = "Image scan finished with \(missingPluginImageCount) plugin images still unresolved."
        }
    }

    func requestPluginImage(for plugin: PluginItem, familyID: String, liveVersion: String) {
        guard !isPreparing, let imagePath = manifest.plugins[familyID] else { return }
        guard !requestedPlugins.contains(familyID) else { return }
        requestedPlugins.insert(familyID)
        Task {
            if let image = NSImage(contentsOfFile: imagePath) {
                pluginImages[familyID] = image
                pluginImageOrder.append(familyID)
                if pluginImageOrder.count > 80 {
                    let oldest = pluginImageOrder.removeFirst()
                    pluginImages.removeValue(forKey: oldest)
                    requestedPlugins.remove(oldest)
                }
            }
        }
    }

    func requestVendorImage(vendor: String, plugins: [PluginItem], liveVersion: String) {
        let key = Self.normalized(vendor)
        guard !isPreparing, let imagePath = manifest.vendors[key] else { return }
        guard !requestedVendors.contains(key) else { return }
        requestedVendors.insert(key)
        Task {
            if let image = NSImage(contentsOfFile: imagePath) {
                vendorImages[key] = image
                vendorImageOrder.append(key)
                if vendorImageOrder.count > 60 {
                    let oldest = vendorImageOrder.removeFirst()
                    vendorImages.removeValue(forKey: oldest)
                    requestedVendors.remove(oldest)
                }
            }
        }
    }

    func captureLivePluginWindowIfNeeded(for plugin: PluginItem, familyID: String) {
        guard manifest.plugins[familyID] == nil,
              !capturingPlugins.contains(familyID),
              PluginArtworkExtractor.loadOverrides().plugins[familyID] == nil else { return }
        capturingPlugins.insert(familyID)
        Task {
            defer { capturingPlugins.remove(familyID) }
            guard CGPreflightScreenCaptureAccess() else { return }
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
                let image = await Task.detached(priority: .utility) {
                    PluginArtworkExtractor.captureLivePluginWindow(named: plugin.name)
                }.value
                guard let image else { continue }
                guard let url = PluginArtworkExtractor.cacheCapturedImage(image, pluginID: familyID) else { return }
                manifest.plugins[familyID] = url.path
                PluginArtworkExtractor.saveManifest(manifest)
                artworkRevision += 1
                return
            }
        }
    }

    nonisolated static func normalized(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }
}

private struct ArtworkManifest: Codable {
    var key = ""
    var plugins: [String: String] = [:]
    var vendors: [String: String] = [:]
}

private struct ArtworkOverrides: Codable {
    var plugins: [String: String] = [:]
    var vendors: [String: String] = [:]
}

private struct SupportImage {
    let url: URL
    let stemKey: String
}

private enum HostedVST3ArtworkCapture {
    static let minimumWaitSeconds = 1.10
    static let timeoutSeconds = 25.0
    struct Result {
        let image: CGImage
        let rejectedWindows: Int
        let firstVisibleSeconds: Double
    }
    private struct CaptureError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func capture(plugin: PluginItem, liveVersion: String) throws -> Result {
        let bundle = try AbletonPluginScanner.resourceBundleURL(for: plugin, liveVersion: liveVersion)
        let helper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/BubblePlugCapture")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw CaptureError(message: "The bundled VST3 image helper is missing.")
        }
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--name", plugin.name, bundle.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { throw CaptureError(message: "Could not start the VST3 image helper: \(error.localizedDescription)") }
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }
        let started = Date()
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var rejectedWindows = 0
        var firstVisibleSeconds: Double?
        var lastUsableImage: CGImage?
        var usableSince: Date?
        while process.isRunning && Date() < deadline {
            if let image = captureWindow(processID: process.processIdentifier) {
                if hasVisibleContent(image) {
                    if firstVisibleSeconds == nil { firstVisibleSeconds = Date().timeIntervalSince(started) }
                    if usableSince == nil { usableSince = Date() }
                    lastUsableImage = image
                } else {
                    rejectedWindows += 1
                    usableSince = nil
                    lastUsableImage = nil
                }
            } else {
                usableSince = nil
                lastUsableImage = nil
            }
            if let image = lastUsableImage,
               let usableSince,
               Date().timeIntervalSince(started) >= minimumWaitSeconds,
               Date().timeIntervalSince(usableSince) >= 0.35 {
                return Result(image: image, rejectedWindows: rejectedWindows,
                              firstVisibleSeconds: firstVisibleSeconds ?? timeoutSeconds)
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        if !process.isRunning {
            throw CaptureError(message: "The VST3 helper exited before its editor was captured (status \(process.terminationStatus), rejectedWindows=\(rejectedWindows), elapsed=\(String(format: "%.2f", Date().timeIntervalSince(started)))s).")
        }
        throw CaptureError(message: "The VST3 editor did not produce a visible image within \(Int(timeoutSeconds)) seconds (rejectedWindows=\(rejectedWindows)).")
    }

    private static func captureWindow(processID: Int32) -> CGImage? {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        let candidates = windows.compactMap { window -> (CGWindowID, Int)? in
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid == processID,
                  let rawBounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary),
                  bounds.width >= 150, bounds.height >= 100,
                  let number = window[kCGWindowNumber as String] as? NSNumber else { return nil }
            return (CGWindowID(number.uint32Value), Int(bounds.width * bounds.height))
        }.sorted { $0.1 > $1.1 }
        for (windowID, _) in candidates {
            if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID,
                                                   [.bestResolution, .boundsIgnoreFraming]) {
                return image
            }
        }
        return nil
    }

    static func hasVisibleContent(_ image: CGImage) -> Bool {
        let side = 64
        let top = min(80, image.height / 5)
        let sampledImage = image.cropping(to: CGRect(x: 0, y: top, width: image.width,
                                                    height: image.height - top)) ?? image
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let pointer = buffer.baseAddress,
                  let context = CGContext(data: pointer, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(sampledImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var levels = [Int]()
            levels.reserveCapacity(side * side)
            for offset in stride(from: 0, to: side * side * 4, by: 4) {
                levels.append(Int(max(bytes[offset], bytes[offset + 1], bytes[offset + 2])))
            }
            let median = levels.sorted()[levels.count / 2]
            let detailedPixels = levels.reduce(0) { count, level in
                count + (abs(level - median) >= 15 ? 1 : 0)
            }
            return detailedPixels >= 20
        }
    }
}

private enum PluginArtworkExtractor {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "bmp"]
    private static let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PlugSpot/Artwork", isDirectory: true)
    private static var manifestURL: URL { cacheDirectory.appendingPathComponent("manifest.json") }
    private static let customDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/PlugSpot/CustomArtwork", isDirectory: true)
    private static var overridesURL: URL { customDirectory.appendingPathComponent("overrides.json") }

    static func appendCaptureLog(_ line: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PlugSpot", isDirectory: true)
        let url = directory.appendingPathComponent("artwork-capture.log")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n".data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: data)
        } else if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        }
    }

    static func loadOverrides() -> ArtworkOverrides {
        guard let data = try? Data(contentsOf: overridesURL),
              let result = try? JSONDecoder().decode(ArtworkOverrides.self, from: data) else { return ArtworkOverrides() }
        return result
    }

    static func saveOverrides(_ overrides: ArtworkOverrides) {
        try? FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(overrides) { try? data.write(to: overridesURL, options: .atomic) }
    }

    static func saveManifest(_ manifest: ArtworkManifest) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(manifest) { try? data.write(to: manifestURL, options: .atomic) }
    }

    static func cacheCapturedImage(_ image: CGImage, pluginID: String) -> URL? {
        let name = digest("captured-plugin-window|\(pluginID)|\(UUID().uuidString)")
        let outputURL = cacheDirectory.appendingPathComponent("\(name).jpg")
        let scale = min(1, 384 / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let thumbnail = context.makeImage() else { return nil }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return outputURL
        } catch {
            return nil
        }
    }

    static func captureLivePluginWindow(named pluginName: String) -> CGImage? {
        let wanted = PluginArtworkStore.normalized(pluginName)
        guard wanted.count >= 3 else { return nil }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.ableton.live")
        let livePIDs = Set(running.map(\.processIdentifier))
        guard !livePIDs.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let matches = windows.compactMap { window -> (CGWindowID, Int)? in
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  livePIDs.contains(pid),
                  let title = window[kCGWindowName as String] as? String,
                  PluginArtworkStore.normalized(title).contains(wanted),
                  let rawBounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary),
                  bounds.width >= 300, bounds.height >= 180,
                  let number = window[kCGWindowNumber as String] as? NSNumber else { return nil }
            return (CGWindowID(number.uint32Value), Int(bounds.width * bounds.height))
        }.sorted { $0.1 > $1.1 }
        for (windowID, _) in matches {
            if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.bestResolution]) {
                return image
            }
        }
        return nil
    }

    static func copyCustomImage(_ source: URL) -> URL? {
        guard NSImage(contentsOf: source) != nil else { return nil }
        let name = digest(source.path + "|" + UUID().uuidString)
        let target = customDirectory.appendingPathComponent("\(name).\(source.pathExtension.lowercased())")
        do {
            try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
            return target
        } catch { return nil }
    }

    static func cachedImagePath(at source: URL, role: String) -> String? {
        cacheImage(at: source, role: role)?.path
    }

    static func catalogKey(plugins: [(id: String, item: PluginItem)], liveVersion: String) -> String {
        let catalog = plugins.map { "\($0.id)|\($0.item.id)|\($0.item.name)|\($0.item.vendor ?? "")" }.sorted().joined(separator: "\n")
        return digest("artwork-v5|\(liveVersion)|\(catalog)")
    }

    static func loadManifest() -> ArtworkManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        guard let saved = try? JSONDecoder().decode(ArtworkManifest.self, from: data),
              (Array(saved.plugins.values) + Array(saved.vendors.values)).allSatisfy({ FileManager.default.fileExists(atPath: $0) }) else { return nil }
        return saved
    }

    static func prepare(
        plugins: [(id: String, item: PluginItem)], liveVersion: String, key: String,
        progress: @escaping @Sendable (Double) -> Void
    ) -> ArtworkManifest {
        var manifest = ArtworkManifest(key: key)
        let activePluginIDs = Set(plugins.map(\.id))
        let vendorGroups = Dictionary(grouping: plugins) { PluginArtworkStore.normalized($0.item.vendor ?? "") }
        let activeVendorKeys = Set(vendorGroups.keys.filter { !$0.isEmpty })
        if let saved = loadManifest() {
            manifest.plugins = saved.plugins.filter { activePluginIDs.contains($0.key) }
            manifest.vendors = saved.vendors.filter { activeVendorKeys.contains($0.key) }
        }
        progress(0.01)
        let supportImages: [SupportImage] = []
        progress(0.05)
        let total = max(plugins.count + vendorGroups.count, 1)
        var completed = 0

        for entry in plugins {
            if Task<Never, Never>.isCancelled { return manifest }
            if manifest.plugins[entry.id] != nil {
                completed += 1
                progress(0.05 + 0.95 * Double(completed) / Double(total))
                continue
            }
            let vendor = entry.item.vendor ?? ""
            let found = findSupportPluginArtwork(in: supportImages, name: entry.item.name, vendor: vendor)
                ?? (try? AbletonPluginScanner.resourceBundleURL(for: entry.item, liveVersion: liveVersion))
                    .flatMap { findPluginArtwork(in: $0, pluginName: entry.item.name) }
            if let found, let cached = cacheImage(at: found, role: "plugin") {
                manifest.plugins[entry.id] = cached.path
            }
            completed += 1
            progress(0.05 + 0.95 * Double(completed) / Double(total))
        }
        for (vendorKey, entries) in vendorGroups where !vendorKey.isEmpty {
            if Task<Never, Never>.isCancelled { return manifest }
            if manifest.vendors[vendorKey] != nil {
                completed += 1
                progress(0.05 + 0.95 * Double(completed) / Double(total))
                continue
            }
            let vendor = entries[0].item.vendor ?? ""
            let found = findSupportVendorLogo(in: supportImages, vendor: vendor)
                ?? entries.prefix(16).lazy.compactMap { try? AbletonPluginScanner.resourceBundleURL(for: $0.item, liveVersion: liveVersion) }
                    .compactMap { findVendorLogo(in: $0, vendor: vendor) }.first
            if let found, let cached = cacheImage(at: found, role: "vendor") {
                manifest.vendors[vendorKey] = cached.path
            }
            completed += 1
            progress(0.05 + 0.95 * Double(completed) / Double(total))
        }
        let overrides = loadOverrides()
        for (id, path) in overrides.plugins where plugins.contains(where: { $0.id == id }) {
            if let cached = cacheImage(at: URL(fileURLWithPath: path), role: "plugin") { manifest.plugins[id] = cached.path }
        }
        for (key, path) in overrides.vendors where vendorGroups[key] != nil {
            if let cached = cacheImage(at: URL(fileURLWithPath: path), role: "vendor") { manifest.vendors[key] = cached.path }
        }
        if Task<Never, Never>.isCancelled { return manifest }
        saveManifest(manifest)
        return manifest
    }

    private static func digest(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func applicationSupportImages(vendors: [String]) -> [SupportImage] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Library/Application Support", isDirectory: true),
            URL(fileURLWithPath: "/Library/Application Support", isDirectory: true),
        ]
        let vendorKeys = vendors.map { PluginArtworkStore.normalized($0.components(separatedBy: "(").first ?? $0) }
            .filter { $0.count >= 4 }
        var vendorRoots: [URL] = []
        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children {
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let directoryKey = PluginArtworkStore.normalized(child.lastPathComponent)
                if vendorKeys.contains(where: { $0 == directoryKey || ($0.count >= 5 && $0.contains(directoryKey)) || (directoryKey.count >= 5 && directoryKey.contains($0)) }) {
                    vendorRoots.append(child)
                }
            }
        }
        return imageFiles(in: vendorRoots, recursive: true, maxDepth: 8,
        skipDirectories: ["caches", "cache", "logs", "downloads"])
        .map { url in
            SupportImage(url: url,
                         stemKey: PluginArtworkStore.normalized(url.deletingPathExtension().lastPathComponent))
        }
    }

    private static func findSupportPluginArtwork(in images: [SupportImage], name: String, vendor: String) -> URL? {
        let productKey = PluginArtworkStore.normalized(name)
        let vendorKey = PluginArtworkStore.normalized(vendor.components(separatedBy: "(").first ?? vendor)
        guard productKey.count >= 4, vendorKey.count >= 3 else { return nil }
        return images.compactMap { image -> (URL, Int)? in
            let components = image.url.deletingLastPathComponent().pathComponents.map(PluginArtworkStore.normalized)
            guard components.contains(where: { $0 == vendorKey || ($0.count >= 5 && ($0.contains(vendorKey) || vendorKey.contains($0))) }),
                  isExactProductImage(stem: image.stemKey, pathComponents: components, productKey: productKey),
                  let size = pixelSize(of: image.url),
                  size.width >= 160, size.height >= 100,
                  (0.65...5).contains(size.width / size.height),
                  !isProblemStateArtwork(image.url.lastPathComponent) else { return nil }
            let exactStem = image.stemKey == productKey ? 100 : 0
            return (image.url, exactStem + min(Int(size.width * size.height / 10_000), 120))
        }.max(by: { $0.1 < $1.1 })?.0
    }

    private static func findSupportVendorLogo(in images: [SupportImage], vendor: String) -> URL? {
        let vendorKey = PluginArtworkStore.normalized(vendor)
        guard vendorKey.count >= 3 else { return nil }
        return images.compactMap { image -> (URL, Int)? in
            let components = image.url.deletingLastPathComponent().pathComponents.map(PluginArtworkStore.normalized)
            guard components.contains(where: { $0 == vendorKey || ($0.count >= 5 && ($0.contains(vendorKey) || vendorKey.contains($0))) }),
                  image.stemKey == "logo" || image.stemKey == "\(vendorKey)logo",
                  let size = pixelSize(of: image.url), size.width >= 48, size.height >= 24,
                  size.width <= 2048, size.height <= 2048 else { return nil }
            return (image.url, (image.stemKey == "\(vendorKey)logo" ? 100 : 0) - image.stemKey.count)
        }.max(by: { $0.1 < $1.1 })?.0
    }

    private static func isExactProductImage(stem: String, pathComponents: [String], productKey: String) -> Bool {
        if stem == productKey || pathComponents.contains(productKey) { return true }
        let suffixes = ["preview", "thumbnail", "screenshot", "interface", "gui", "plugin", "product", "cover", "snapshot", "main"]
        return suffixes.contains { stem == productKey + $0 }
    }

    private static func isProblemStateArtwork(_ name: String) -> Bool {
        let key = PluginArtworkStore.normalized(name)
        return ["disabled", "authorization", "expired", "trial", "activation", "licenseerror", "missing", "notfound"]
            .contains(where: key.contains)
    }

    private static func findPluginArtwork(in bundle: URL, pluginName: String) -> URL? {
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        let metadataURL = resources.appendingPathComponent("moduleinfo.json")
        let wantedName = PluginArtworkStore.normalized(pluginName)
        let snapshots = resources.appendingPathComponent("Snapshots", isDirectory: true)
        if let source = try? String(contentsOf: metadataURL, encoding: .utf8),
           let cleaned = source.replacingOccurrences(of: #",\s*([}\]])"#, with: "$1", options: .regularExpression).data(using: .utf8),
           let metadata = try? JSONSerialization.jsonObject(with: cleaned) as? [String: Any],
           let classes = metadata["Classes"] as? [[String: Any]] {
            let audioClasses = classes.filter { ($0["Category"] as? String) == "Audio Module Class" }
            let matching = audioClasses.filter {
                PluginArtworkStore.normalized($0["Name"] as? String ?? "") == wantedName
            }
            let candidates = matching.isEmpty && audioClasses.count == 1 ? audioClasses : matching
            for pluginClass in candidates {
                guard let classID = pluginClass["CID"] as? String,
                      classID.range(of: #"^[0-9A-Fa-f]{32}$"#, options: .regularExpression) != nil else { continue }
                for filename in ["\(classID)_snapshot_2.0x.png", "\(classID)_snapshot.png"] {
                    let image = snapshots.appendingPathComponent(filename)
                    if FileManager.default.fileExists(atPath: image.path), pixelSize(of: image) != nil { return image }
                }
            }
        }
        let productKey = PluginArtworkStore.normalized(pluginName)
        guard !productKey.isEmpty else { return nil }
        let artworkDirectories = ["Artwork", "Art", "Images", "Snapshots"].map {
            resources.appendingPathComponent($0, isDirectory: true)
        }
        let resourceImages = imageFiles(in: [resources], recursive: false)
            + imageFiles(in: artworkDirectories, recursive: true, maxDepth: 2,
                         skipDirectories: ["scripts", "presets", "fonts", "cache"])
        let componentsForBundle = bundle.pathComponents.map(PluginArtworkStore.normalized)
        return resourceImages.compactMap { image -> (URL, Int)? in
            let stem = PluginArtworkStore.normalized(image.deletingPathExtension().lastPathComponent)
            let components = image.deletingLastPathComponent().pathComponents.map(PluginArtworkStore.normalized)
            guard isExactProductImage(stem: stem, pathComponents: components, productKey: productKey),
                  let size = pixelSize(of: image), size.width >= 160, size.height >= 100,
                  (0.65...5).contains(size.width / size.height),
                  !isProblemStateArtwork(image.lastPathComponent) else { return nil }
            let score = (stem == productKey ? 100 : 0) + (componentsForBundle.contains(productKey) ? 25 : 0)
            return (image, score)
        }.max(by: { $0.1 < $1.1 })?.0
    }

    private static func findVendorLogo(in bundle: URL, vendor: String) -> URL? {
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        let files = imageFiles(in: [resources], recursive: true, maxDepth: 3, skipDirectories: ["graphics", "skin", "scripts", "presets"])
        let vendorKey = PluginArtworkStore.normalized(vendor)
        let ranked = files.compactMap { url -> (URL, Int)? in
            let stem = PluginArtworkStore.normalized(url.deletingPathExtension().lastPathComponent)
            guard stem.contains("logo"), let size = pixelSize(of: url),
                  size.width >= 48, size.height >= 24,
                  size.width <= 2048, size.height <= 2048 else { return nil }
            let relativePath = url.path.components(separatedBy: "/Contents/Resources/").last ?? url.lastPathComponent
            let vendorNamed = stem.contains(vendorKey) || PluginArtworkStore.normalized(relativePath).contains(vendorKey)
            let imageRatio = size.width / size.height
            guard imageRatio >= 0.25, imageRatio <= 7 else { return nil }
            let score = (vendorNamed ? 1000 : 0) + (imageRatio > 0.6 && imageRatio < 2.2 ? 80 : 0) - min(stem.count, 120)
            return (url, score)
        }
        return ranked.max(by: { $0.1 < $1.1 })?.0
    }

    private static func imageFiles(
        in roots: [URL],
        recursive: Bool,
        maxDepth: Int = 6,
        skipDirectories: Set<String> = []
    ) -> [URL] {
        let fileManager = FileManager.default
        var result: [URL] = []
        var visited = Set<String>()

        func visit(_ directory: URL, depth: Int) {
            guard depth <= maxDepth, visited.insert(directory.standardizedFileURL.path).inserted,
                  let children = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                  ) else { return }
            for child in children {
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    let name = child.lastPathComponent.lowercased()
                    if recursive && !skipDirectories.contains(name) { visit(child, depth: depth + 1) }
                } else if imageExtensions.contains(child.pathExtension.lowercased()) {
                    result.append(child)
                }
            }
        }

        for root in roots { visit(root, depth: 0) }
        return result
    }

    private static func pixelSize(of url: URL) -> (width: CGFloat, height: CGFloat)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        return (CGFloat(width.doubleValue), CGFloat(height.doubleValue))
    }

    private static func cacheImage(at sourceURL: URL, role: String) -> URL? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: sourceURL.path) else { return nil }
        let size = (attributes[.size] as? NSNumber)?.stringValue ?? "0"
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let sourceKey = "\(role)|\(sourceURL.path)|\(size)|\(modified)"
        let digest = SHA256.hash(data: Data(sourceKey.utf8)).map { String(format: "%02x", $0) }.joined()
        let preservesAlpha = role == "vendor" || !["jpg", "jpeg"].contains(sourceURL.pathExtension.lowercased())
        let outputExtension = preservesAlpha ? "png" : "jpg"
        let outputURL = cacheDirectory.appendingPathComponent("\(digest).\(outputExtension)")
        if FileManager.default.fileExists(atPath: outputURL.path) { return outputURL }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: role == "vendor" ? 160 : 384,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else { return nil }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let type = preservesAlpha ? UTType.png.identifier : UTType.jpeg.identifier
            guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, type as CFString, 1, nil) else { return nil }
            let properties: [CFString: Any] = preservesAlpha
                ? [:]
                : [kCGImageDestinationLossyCompressionQuality: 0.78]
            CGImageDestinationAddImage(destination, thumbnail, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return outputURL
        } catch {
            return nil
        }
    }

}
