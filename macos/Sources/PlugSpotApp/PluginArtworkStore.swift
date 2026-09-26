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
    @Published private(set) var pluginImages: [String: NSImage] = [:]
    @Published private(set) var vendorImages: [String: NSImage] = [:]

    private var requestedPlugins: Set<String> = []
    private var requestedVendors: Set<String> = []

    func requestPluginImage(for plugin: PluginItem, familyID: String, liveVersion: String) {
        guard !requestedPlugins.contains(familyID) else { return }
        requestedPlugins.insert(familyID)
        Task {
            let imagePath = await Task.detached(priority: .utility) {
                PluginArtworkExtractor.pluginImagePath(for: plugin, liveVersion: liveVersion)
            }.value
            if let imagePath, let image = NSImage(contentsOfFile: imagePath) {
                pluginImages[familyID] = image
            }
        }
    }

    func requestVendorImage(vendor: String, plugins: [PluginItem], liveVersion: String) {
        let key = Self.normalized(vendor)
        guard !requestedVendors.contains(key) else { return }
        requestedVendors.insert(key)
        Task {
            let imagePath = await Task.detached(priority: .utility) {
                PluginArtworkExtractor.vendorImagePath(for: vendor, plugins: plugins, liveVersion: liveVersion)
            }.value
            if let imagePath, let image = NSImage(contentsOfFile: imagePath) {
                vendorImages[key] = image
            }
        }
    }

    nonisolated static func normalized(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }
}

private enum PluginArtworkExtractor {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "bmp"]
    private static let ignoredArtworkTokens = ["button", "icon", "mask", "background", "toolbar", "control", "knob", "slider"]
    private static let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PlugSpot/Artwork", isDirectory: true)

    static func pluginImagePath(for plugin: PluginItem, liveVersion: String) -> String? {
        guard let bundle = try? AbletonPluginScanner.resourceBundleURL(for: plugin, liveVersion: liveVersion),
              let source = findPluginArtwork(in: bundle, pluginName: plugin.name) else { return nil }
        return cacheImage(at: source, role: "plugin")?.path
    }

    static func vendorImagePath(for vendor: String, plugins: [PluginItem], liveVersion: String) -> String? {
        for plugin in plugins.prefix(16) {
            guard let bundle = try? AbletonPluginScanner.resourceBundleURL(for: plugin, liveVersion: liveVersion),
                  let source = findVendorLogo(in: bundle, vendor: vendor),
                  let cached = cacheImage(at: source, role: "vendor") else { continue }
            return cached.path
        }
        return nil
    }

    private static func findPluginArtwork(in bundle: URL, pluginName: String) -> URL? {
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        let normalizedName = PluginArtworkStore.normalized(pluginName)
        guard !normalizedName.isEmpty else { return nil }

        let searchDirectories = [
            resources.appendingPathComponent("Snapshots", isDirectory: true),
            resources.appendingPathComponent("Artwork", isDirectory: true),
            resources.appendingPathComponent("Art", isDirectory: true),
            resources.appendingPathComponent("Html/images", isDirectory: true),
            resources,
        ]
        let candidates = imageFiles(
            in: searchDirectories,
            recursive: true,
            skipDirectories: ["graphics", "skin", "scripts", "presets", "fonts"]
        ).compactMap { url -> (URL, Int)? in
            let stem = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "@2x", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "@3x", with: "", options: .caseInsensitive)
            let normalizedStem = PluginArtworkStore.normalized(stem)
            let isSnapshot = url.path.localizedCaseInsensitiveContains("/Snapshots/")
            guard normalizedStem.contains(normalizedName) || isSnapshot,
                  !ignoredArtworkTokens.contains(where: { normalizedStem.contains($0) }),
                  let size = pixelSize(of: url), size.width >= 240, size.height >= 135,
                  size.width / size.height >= 1.1, size.width / size.height <= 3.2 else { return nil }
            let isHtmlImage = url.path.localizedCaseInsensitiveContains("/Html/images/")
            let exactProductName = normalizedStem == normalizedName
            let score = (isSnapshot ? 1000 : 0) + (exactProductName ? 400 : 0) + (isHtmlImage ? 100 : 0) - normalizedStem.count
            return (url, score)
        }
        return candidates.max(by: { $0.1 < $1.1 })?.0
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
            kCGImageSourceThumbnailMaxPixelSize: role == "vendor" ? 256 : 640,
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
            pruneCacheIfNeeded()
            return outputURL
        } catch {
            return nil
        }
    }

    private static func pruneCacheIfNeeded() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let fileSize = values.fileSize else { return nil }
            return (url, fileSize, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var totalSize = entries.reduce(0) { $0 + $1.1 }
        guard totalSize > 32 * 1024 * 1024 else { return }
        for entry in entries where totalSize > 24 * 1024 * 1024 {
            try? fileManager.removeItem(at: entry.0)
            totalSize -= entry.1
        }
    }
}
