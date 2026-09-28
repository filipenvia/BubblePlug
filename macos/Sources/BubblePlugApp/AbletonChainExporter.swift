import AppKit
import Foundation
import BubblePlugCore

enum AbletonChainExportError: LocalizedError {
    case emptyChain
    case unsupportedFormat(String)
    case unsupportedOrder(String)
    case invalidPluginID(String)
    case missingTemplate(String)
    case invalidTemplate
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .emptyChain:
            return "This Chain Set has no plugins to export."
        case .unsupportedFormat(let name):
            return "\(name) is not a VST3 plugin. Ableton rack export currently supports VST3 only."
        case .unsupportedOrder(let detail):
            return "This plugin order cannot be represented by one Ableton rack. \(detail)"
        case .invalidPluginID(let name):
            return "BubblePlug could not read the exact VST3 ID for \(name). Refresh the plugin library and save the Chain Set again."
        case .missingTemplate(let name):
            return "BubblePlug is missing its Ableton \(name) template. Reinstall BubblePlug and try again."
        case .invalidTemplate:
            return "BubblePlug could not prepare a valid Ableton rack preset."
        case .compressionFailed:
            return "BubblePlug could not package the rack as an Ableton .adg file."
        }
    }
}

enum AbletonChainExporter {
    private enum RackKind {
        case audioEffect
        case instrument
    }

    private struct PluginIdentity {
        let chainPlugin: StoredChainPlugin
        let type: String
        let uidFields: [Int32]
        let uri: String
    }

    static func validate(_ chainSet: StoredChainSet, liveVersion: String) throws {
        _ = try identities(for: chainSet, liveVersion: liveVersion)
    }

    static func export(_ chainSet: StoredChainSet, to destination: URL, liveVersion: String) throws {
        let plugins = try identities(for: chainSet, liveVersion: liveVersion)
        let rackKind = try rackKind(for: plugins)
        let document = try makeDocument(for: rackKind)
        try populate(document, chainSet: chainSet, plugins: plugins, rackKind: rackKind)

        guard let xml = document.xmlData(options: [.nodePrettyPrint, .nodeCompactEmptyElement]) as Data? else {
            throw AbletonChainExportError.invalidTemplate
        }
        let compressed = try gzip(xml)
        try compressed.write(to: destination, options: .atomic)
    }

    private static func identities(for set: StoredChainSet, liveVersion: String) throws -> [PluginIdentity] {
        guard !set.plugins.isEmpty else { throw AbletonChainExportError.emptyChain }
        return try set.plugins.map { plugin in
            guard plugin.format.caseInsensitiveCompare("VST3") == .orderedSame else {
                throw AbletonChainExportError.unsupportedFormat(plugin.name)
            }
            let exactID = try exactDeviceClassID(for: plugin, liveVersion: liveVersion)
            let parts = exactID.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0] == "device", parts[1] == "vst3",
                  ["audiofx", "instr", "midifx"].contains(String(parts[2])),
                  let uuid = UUID(uuidString: String(parts[3])) else {
                throw AbletonChainExportError.invalidPluginID(plugin.name)
            }
            let bytes = uuid.uuid
            let fields = withUnsafeBytes(of: bytes) { rawBuffer -> [Int32] in
                stride(from: 0, to: rawBuffer.count, by: 4).map { offset in
                    let value = UInt32(rawBuffer[offset]) << 24
                        | UInt32(rawBuffer[offset + 1]) << 16
                        | UInt32(rawBuffer[offset + 2]) << 8
                        | UInt32(rawBuffer[offset + 3])
                    return Int32(bitPattern: value)
                }
            }
            return PluginIdentity(chainPlugin: plugin, type: String(parts[2]), uidFields: fields, uri: exactID)
        }
    }

    private static func exactDeviceClassID(for plugin: StoredChainPlugin, liveVersion: String) throws -> String {
        if plugin.pluginID.hasPrefix("device:vst3:") {
            let id = plugin.pluginID.split(separator: "?", maxSplits: 1).first.map(String.init) ?? plugin.pluginID
            if id.range(of: #"^device:vst3:(audiofx|instr|midifx):[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#, options: .regularExpression) != nil {
                return id
            }
        }

        // Live's Browser returns query URIs, while rack presets store the class ID.
        // Extract the exact Browser display name (including channel variants) and
        // resolve that against Live's own VST3 scanner record.
        let prefix = "query:Plugins#VST3:"
        let queryTail = plugin.pluginID.hasPrefix(prefix) ? String(plugin.pluginID.dropFirst(prefix.count)) : ""
        let browserParts = queryTail.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let browserVendor = browserParts.first.map(String.init)?.removingPercentEncoding
        let browserName = browserParts.count > 1 ? String(browserParts[1]).removingPercentEncoding : nil
        guard let vendor = (browserVendor?.isEmpty == false ? browserVendor : plugin.vendor) else {
            throw AbletonChainExportError.invalidPluginID(plugin.name)
        }

        if let browserName, !browserName.isEmpty,
           let id = try? AbletonPluginScanner.deviceClassID(for: browserName, vendor: vendor, liveVersion: liveVersion) {
            return id
        }
        if let id = try? AbletonPluginScanner.deviceClassID(for: plugin.name, vendor: vendor, liveVersion: liveVersion) {
            return id
        }
        throw AbletonChainExportError.invalidPluginID(plugin.name)
    }

    private static func rackKind(for plugins: [PluginIdentity]) throws -> RackKind {
        if plugins.allSatisfy({ $0.type == "audiofx" }) { return .audioEffect }
        if plugins.first?.type == "instr" {
            guard plugins.dropFirst().allSatisfy({ $0.type == "audiofx" }) else {
                throw AbletonChainExportError.unsupportedOrder("An instrument must be first and can be followed by audio effects; a rack cannot serially host multiple instruments or MIDI effects.")
            }
            return .instrument
        }
        if plugins.contains(where: { $0.type == "midifx" }) {
            throw AbletonChainExportError.unsupportedOrder("MIDI-effect racks are not supported by this export yet.")
        }
        throw AbletonChainExportError.unsupportedOrder("Put the instrument first, followed by any audio effects.")
    }

    private static func makeDocument(for kind: RackKind) throws -> XMLDocument {
        switch kind {
        case .instrument:
            guard let url = Bundle.main.url(forResource: "InstrumentRackTemplate", withExtension: "xml"),
                  let data = try? Data(contentsOf: url),
                  let document = try? XMLDocument(data: data, options: [.nodePreserveAll]) else {
                throw AbletonChainExportError.missingTemplate("Instrument Rack")
            }
            return document
        case .audioEffect:
            guard let url = Bundle.main.url(forResource: "AudioEffectRackTemplate", withExtension: "adg") else {
                throw AbletonChainExportError.missingTemplate("Audio Effect Rack")
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
            process.arguments = ["-dc", url.path]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            do { try process.run() } catch { throw AbletonChainExportError.invalidTemplate }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let document = try? XMLDocument(data: data, options: [.nodePreserveAll]) else {
                throw AbletonChainExportError.invalidTemplate
            }
            return document
        }
    }

    private static func populate(_ document: XMLDocument, chainSet: StoredChainSet, plugins: [PluginIdentity], rackKind: RackKind) throws {
        guard let group = document.rootElement()?.elements(forName: "GroupDevicePreset").first,
              let device = group.elements(forName: "Device").first,
              let rack = device.children?.compactMap({ $0 as? XMLElement }).first(where: {
                  $0.name == (rackKind == .instrument ? "InstrumentGroupDevice" : "AudioEffectGroupDevice")
              }),
              let branches = group.elements(forName: "BranchPresets").first,
              let branch = branches.children?.compactMap({ $0 as? XMLElement }).first(where: {
                  $0.name == (rackKind == .instrument ? "InstrumentBranchPreset" : "AudioEffectBranchPreset")
              }),
              let devicePresets = branch.elements(forName: "DevicePresets").first else {
            throw AbletonChainExportError.invalidTemplate
        }

        setAttribute("Value", on: rack.elements(forName: "UserName").first, to: chainSet.name)
        setAttribute("Value", on: branch.elements(forName: "Name").first, to: chainSet.name)

        let sourcePresetDocument = try makeDocument(for: .instrument)
        guard let sourcePreset = sourcePresetDocument.rootElement()?
            .elements(forName: "GroupDevicePreset").first?
            .elements(forName: "BranchPresets").first?
            .elements(forName: "InstrumentBranchPreset").first?
            .elements(forName: "DevicePresets").first?
            .elements(forName: "Vst3Preset").first else {
            throw AbletonChainExportError.invalidTemplate
        }

        devicePresets.setChildren([])
        for (index, plugin) in plugins.enumerated() {
            guard let copied = sourcePreset.copy() as? XMLElement else { throw AbletonChainExportError.invalidTemplate }
            copied.attribute(forName: "Id")?.stringValue = String(index)
            guard let uid = copied.elements(forName: "Uid").first else { throw AbletonChainExportError.invalidTemplate }
            for field in 0..<4 {
                setAttribute("Value", on: uid.elements(forName: "Fields.\(field)").first, to: String(plugin.uidFields[field]))
            }
            setAttribute("Value", on: copied.elements(forName: "Name").first, to: plugin.chainPlugin.name)
            devicePresets.addChild(copied)
        }

        if let sourceContext = branch.elements(forName: "SourceContext").first {
            sourceContext.setChildren([])
            let branchContext = XMLElement(name: "BranchSourceContext")
            branchContext.addAttribute(XMLNode.attribute(withName: "Id", stringValue: "0") as! XMLNode)
            branchContext.addChild(XMLElement(name: "OriginalFileRef"))
            let browserPath = XMLElement(name: "BrowserContentPath")
            browserPath.addAttribute(XMLNode.attribute(withName: "Value", stringValue: browserContentPath(for: plugins[0].chainPlugin)) as! XMLNode)
            branchContext.addChild(browserPath)
            let localFilters = XMLElement(name: "LocalFiltersJson")
            localFilters.addAttribute(XMLNode.attribute(withName: "Value", stringValue: "{\"local-filters\":{\"devarch\":[\"plugin-vst3\"]}}") as! XMLNode)
            branchContext.addChild(localFilters)
            branchContext.addChild(XMLElement(name: "PresetRef"))
            let branchID = XMLElement(name: "BranchDeviceId")
            branchID.addAttribute(XMLNode.attribute(withName: "Value", stringValue: plugins[0].uri) as! XMLNode)
            branchContext.addChild(branchID)
            sourceContext.addChild(branchContext)
        }

        let extraBranches = (branches.children ?? []).compactMap { $0 as? XMLElement }.filter { $0 !== branch }
        for extra in extraBranches { branches.removeChild(at: extra.index) }
        setAttribute("Value", on: group.elements(forName: "OverwriteProtectionNumber").first, to: "3075")
    }

    private static func browserContentPath(for plugin: StoredChainPlugin) -> String {
        "view:X-Plugins#\(plugin.vendor):\(plugin.name)"
    }

    private static func setAttribute(_ name: String, on element: XMLElement?, to value: String) {
        guard let element else { return }
        if let attribute = element.attribute(forName: name) {
            attribute.stringValue = value
        } else {
            element.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
        }
    }

    private static func gzip(_ xml: Data) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-n", "-c"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { throw AbletonChainExportError.compressionFailed }
        do {
            try input.fileHandleForWriting.write(contentsOf: xml)
            try input.fileHandleForWriting.close()
        } catch {
            process.terminate()
            throw AbletonChainExportError.compressionFailed
        }
        let compressed = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, compressed.starts(with: [0x1f, 0x8b]) else {
            throw AbletonChainExportError.compressionFailed
        }
        return compressed
    }
}
