import PlugSpotCore
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

@main
struct PlugSpotApp: App {
    // The startup scene is replaced by a custom NSPanel that hosts a second
    // PlugSpotView. Keep capture state app-scoped so both views cannot start
    // independent scans for the same catalog.
    @StateObject private var artworkStore = PluginArtworkStore()
    @State private var imageProgressPanel = ImageCaptureProgressPanel()

    var body: some Scene {
        WindowGroup {
            PlugSpotView(artworkStore: artworkStore, imageProgressPanel: imageProgressPanel)
                .frame(minWidth: 440, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit BubblePlug") {
                    requestPlugSpotQuit()
                }
                .keyboardShortcut("q")
            }
        }
    }
}

private func requestPlugSpotQuit() {
    let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/PlugSpot", isDirectory: true)
    let quitRequest = supportDirectory.appendingPathComponent("user-quit.request")
    do {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try Data("user-requested".utf8).write(to: quitRequest, options: .atomic)
    } catch {
        NSLog("PlugSpot could not record the requested quit: %@", error.localizedDescription)
    }
    NSApp.terminate(nil)
}

private func openScreenRecordingSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
    NSWorkspace.shared.open(url)
}

private struct AboutBubblePlugView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development build"
    }

    var body: some View {
        VStack(spacing: 14) {
            PlugSpotAudioMark(size: 82)
            VStack(spacing: 4) {
                Text("BubblePlug")
                    .font(.title2.weight(.bold))
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Text("A visual plug-in library and chain manager for Ableton Live.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Made for music production", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.medium))
                .foregroundStyle(PlugSpotPalette.cyan)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 340)
        .modifier(BubblePlugSurface())
    }
}

private struct PlugSpotView: View {
    @State private var bubbleController: PlugSpotBubbleController
    @StateObject private var artworkStore: PluginArtworkStore
    private let imageProgressPanel: ImageCaptureProgressPanel
    @State private var didInitializeWindow = false
    @State private var windowButtonTarget: PlugSpotWindowButtonTarget?
    @State private var scope: PluginListScope = .all
    @State private var isMixerVisible = false
    @State private var isAboutPresented = false
    @AppStorage("plugspot.displayMode") private var displayModeRaw = PluginDisplayMode.list.rawValue
    @AppStorage("plugspot.cachedLiveVersion") private var cachedLiveVersion = ""
    @AppStorage("plugspot.cachedCatalogJSON") private var cachedCatalogJSON = Data()
    @AppStorage("plugspot.cachedScannerModification") private var cachedScannerModification = 0.0
    @AppStorage("plugspot.bubble.scale") private var bubbleScale = 1.0
    @AppStorage("plugspot.bubble.transparency") private var bubbleTransparency = 0.0
    @AppStorage("plugspot.bubble.position.locked") private var bubblePositionLocked = false
    @AppStorage("plugspot.images.startupMode") private var imageStartupMode = "ask"
    @AppStorage("plugspot.shortcut.keyCode") private var shortcutKeyCode = 35
    @AppStorage("plugspot.shortcut.modifiers") private var shortcutModifiers = 0x1800
    @AppStorage("plugspot.shortcut.label") private var shortcutLabel = "⌃⌥P"
    @State private var selectedVendorFilter: String?
    @State private var plugins: [PluginItem] = []
    @State private var catalogFamilies: [PluginFamily] = []
    @State private var liveVersion: String?
    @State private var selectedFamilyID: String?
    @State private var selectedVariantID: String?
    @State private var chainQueue: [QueuedPlugin] = []
    @State private var selectedQueuedPluginID: UUID?
    @State private var chainSets: [StoredChainSet] = []
    @State private var activeChainSetID: String?
    @State private var editingChainSetID: String?
    @State private var editingChainSetName = ""
    @State private var favoriteIDs: Set<String> = []
    @State private var favoriteRecords: [LocalPluginRecord] = []
    @State private var recentRecords: [LocalPluginRecord] = []
    @State private var labelsByPlugin: [String: [LocalPluginLabel]] = [:]
    @State private var categories: [LocalCategory] = []
    @State private var selectedCategoryFilters: Set<String> = []
    @State private var searchText = ""
    @State private var status = "Connecting to Ableton Live…"
    @State private var isError = false
    @State private var localStoreError: String?
    @State private var isLoadingLibrary = false
    @State private var isLiveConnected = false
    @State private var isConnectionUnavailable = false
    @State private var isLiveVersionSupported = false
    @State private var connectionMonitor: Task<Void, Never>?
    @State private var refreshAfterCurrentLoad = false
    @State private var loadingPluginID: String?
    @State private var isImportingOrganization = false
    @State private var isCategoryManagerPresented = false
    @State private var isPreparingAbletonExport = false
    @State private var isSettingsPresented = false
    @State private var isMissingArtworkPresented = false
    @State private var artworkManagerShowsImages = false
    @State private var shortcutStatus = ""
    @State private var globalHotKeyController: PlugSpotGlobalHotKeyController?
    @State private var showAbletonExportConfirmation = false
    @State private var showAbletonExportError = false
    @State private var abletonExportError = ""
    @State private var activeExportPanel: NSSavePanel?
    @State private var abletonExportDocument: PlugSpotLibraryDocument?
    @State private var abletonExportPreflight: AbletonExportPreflight?
    private let library = AbletonLibrary()
    private let localStore: LocalLibraryStore? = try? LocalLibraryStore()

    init(
        bubbleController: PlugSpotBubbleController = PlugSpotBubbleController(),
        artworkStore: PluginArtworkStore,
        imageProgressPanel: ImageCaptureProgressPanel
    ) {
        _bubbleController = State(initialValue: bubbleController)
        _artworkStore = StateObject(wrappedValue: artworkStore)
        self.imageProgressPanel = imageProgressPanel
    }

    private var pluginFamilies: [PluginFamily] {
        catalogFamilies
    }

    private var filteredFamilies: [PluginFamily] {
        var scopedFamilies: [PluginFamily]
        switch scope {
        case .all:
            scopedFamilies = pluginFamilies
        case .favorites:
            scopedFamilies = pluginFamilies.filter { favoriteIDs.contains($0.id) }
        case .recent:
            let recentOrder = Dictionary(uniqueKeysWithValues: recentRecords.enumerated().map { ($0.element.id, $0.offset) })
            scopedFamilies = pluginFamilies
                .filter { recentOrder[$0.id] != nil }
                .sorted { (recentOrder[$0.id] ?? .max) < (recentOrder[$1.id] ?? .max) }
        case .vendors:
            guard let selectedVendorFilter else { return [] }
            let vendorKey = normalizedText(selectedVendorFilter)
            scopedFamilies = pluginFamilies.filter { normalizedText($0.vendor) == vendorKey }
        case .chainSets:
            return []
        }
        if scope != .vendors, let selectedVendorFilter {
            let vendorKey = normalizedText(selectedVendorFilter)
            scopedFamilies = scopedFamilies.filter { normalizedText($0.vendor) == vendorKey }
        }
        if !selectedCategoryFilters.isEmpty {
            scopedFamilies = scopedFamilies.filter { family in
                let familyCategories = labelsByPlugin[family.id]?.filter { $0.kind == "category" }.map(\.name) ?? []
                return selectedCategoryFilters.allSatisfy { selectedCategory in
                    familyCategories.contains { $0.caseInsensitiveCompare(selectedCategory) == .orderedSame }
                }
            }
        }
        let query = searchText
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scopedFamilies }
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return scopedFamilies.filter { family in
            let allVariantNames = family.variants.map(\.name).joined(separator: " ")
            let searchable = "\(family.name) \(family.vendor) \(allVariantNames) VST3"
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return terms.allSatisfy { searchable.localizedStandardContains($0) }
        }
    }

    private var selectedFamily: PluginFamily? {
        guard let selectedFamilyID else { return nil }
        return pluginFamilies.first { $0.id == selectedFamilyID }
    }

    private var selectedVariant: PluginItem? {
        guard let selectedFamily else { return nil }
        return selectedFamily.variants.first { $0.id == selectedVariantID }
            ?? selectedFamily.preferredVariant
    }

    private var unavailableFavoriteCount: Int {
        let availableFamilies = Set(pluginFamilies.map(\.id))
        return favoriteRecords.filter { !availableFamilies.contains($0.id) }.count
    }

    private var unavailableRecentCount: Int {
        let availableFamilies = Set(pluginFamilies.map(\.id))
        return recentRecords.filter { !availableFamilies.contains($0.id) }.count
    }

    private var isAbletonLiveRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { application in
            application.bundleIdentifier?.lowercased().hasPrefix("com.ableton.live") == true
                || application.localizedName?.lowercased().contains("ableton live") == true
        }
    }

    private var isRemoteScriptInstalledAtDefaultLocation: Bool {
        let scriptURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music/Ableton/User Library/Remote Scripts/PlugSpot/__init__.py")
        return FileManager.default.fileExists(atPath: scriptURL.path)
    }

    private func scannerModification(for version: String) -> Double {
        let scanner = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/Ableton/Live \(version)/PluginScanner.txt")
        return (try? FileManager.default.attributesOfItem(atPath: scanner.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
    }

    private var bridgeUnavailableMessage: String {
        guard isAbletonLiveRunning else {
            return "Waiting for Ableton Live. PlugSpot will keep trying to connect."
        }
        if isRemoteScriptInstalledAtDefaultLocation {
            return "Ableton Live is open, but the PlugSpot Remote Script isn't responding. In Settings → Link, Tempo & MIDI, select PlugSpot under Control Surface and restart Live. Check ~/Documents/plugspot-remote.log if the problem continues."
        }
        return "Ableton Live is open, but the PlugSpot Remote Script wasn't found in the default User Library. Run macos/install-launcher.sh, check Live's custom User Library location, then restart Live."
    }

    private func isSupportedLiveVersion(_ version: String) -> Bool {
        let components = version.split(separator: ".").compactMap { Int($0) }
        guard components.count >= 3 else { return false }
        return components[0] == 12 && components[1] == 4 && components[2] >= 2
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    isAboutPresented = true
                } label: {
                    PlugSpotAudioMark()
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("About BubblePlug")
                .accessibilityLabel("About BubblePlug")
                Text("BubblePlug")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    isMixerVisible.toggle()
                } label: {
                    Label(isMixerVisible ? "Plugins" : "Mixer", systemImage: isMixerVisible ? "puzzlepiece.extension" : "slider.horizontal.3")
                }
                .help(isMixerVisible ? "Show Plugin Library" : "Show Visual Mixer")
                Button(action: refreshLibrary) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Ableton Live plugin list")
                .disabled(isLoadingLibrary || artworkStore.isCapturingFirstRunImages)
                Menu {
                    Section("Preferences") {
                        Button("Settings…") { isSettingsPresented = true }
                        Button("Manage Categories…") { isCategoryManagerPresented = true }
                    }
                    Section("Ableton Live") {
                        Button("Import Live Collections…", action: importAbletonOrganization)
                            .disabled(isImportingOrganization)
                        Button("Export Collections to Live…", action: prepareAbletonExport)
                            .disabled(isPreparingAbletonExport)
                    }
                    Section("BubblePlug Library") {
                        Button("Import Library Backup…", action: importPlugSpotLibrary)
                        Button("Export Library Backup…", action: exportPlugSpotLibrary)
                    }
                    Section("Plugin Images") {
                        Button("Manage Plugin Images…") { isMissingArtworkPresented = true }
                            .disabled(artworkStore.isPreparing || artworkStore.isCapturingFirstRunImages || catalogFamilies.isEmpty)
                        Button("Load All Plugin Images…", action: loadAllPluginImages)
                            .disabled(artworkStore.isPreparing || artworkStore.isCapturingFirstRunImages || catalogFamilies.isEmpty)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 30, height: 30)
                }
                .help("Settings, Ableton, library and image tools")
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if artworkStore.isPreparing {
                VStack(spacing: 16) {
                    Spacer()
                    PlugSpotAudioMark()
                        .frame(width: 64, height: 64)
                    Text(artworkStore.isCapturingFirstRunImages ? "Capturing VST3 plugin images" : "Preparing plugin images")
                        .font(.title3.weight(.semibold))
                    ProgressView(value: artworkStore.isCapturingFirstRunImages ? artworkStore.captureProgress : artworkStore.preparationProgress)
                        .frame(maxWidth: 380)
                    Text(artworkStore.isCapturingFirstRunImages
                         ? "\(Int(artworkStore.captureProgress * 100))% · \(artworkStore.captureCurrentPlugin)"
                         : "\(Int(artworkStore.preparationProgress * 100))%")
                        .monospacedDigit()
                    Text(artworkStore.isCapturingFirstRunImages
                         ? "BubblePlug opens one plugin editor at a time in its image helper. The scan does not add tracks or plugins to your Live Set."
                         : "Checking exact VST3 snapshots and clearly named local artwork before capturing the remaining plugin editors.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 420)
                    if artworkStore.isCapturingFirstRunImages {
                        Text(artworkStore.captureStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Pause Image Scan") { artworkStore.cancelFirstRunImageCapture() }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if imageStartupMode == "ask" && artworkStore.missingPluginImageCount > 0 && !catalogFamilies.isEmpty {
                VStack(spacing: 14) {
                    PlugSpotAudioMark().frame(width: 56, height: 56)
                    Text("Prepare Plugin Images")
                        .font(.title3.weight(.semibold))
                    Text("\(artworkStore.missingPluginImageCount) plugin images are missing. You can capture them now or open BubblePlug and do this later.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 460)
                    Text("Plugins that need activation or have never been opened may show a setup, activation, or error screen instead of their editor. You can replace any image later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack {
                        Button("Load Images Now") { imageStartupMode = "scan"; loadAllPluginImages() }
                        .buttonStyle(.borderedProminent)
                        Button("Open Without Loading") { imageStartupMode = "defer" }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isMixerVisible {
                MixerView(library: library)
            } else {

            Picker("Plugins", selection: $scope) {
                ForEach(PluginListScope.allCases) { listScope in
                    Text(listScope.title).tag(listScope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .onChange(of: scope) { newScope in
                selectedFamilyID = nil
                selectedVariantID = nil
                if newScope != .vendors { selectedVendorFilter = nil }
                if newScope == .chainSets { loadChainSets() }
            }

            if scope == .chainSets {
                chainSetsView
            } else {
            Group {
            if scope == .vendors, let selectedVendorFilter {
                HStack(spacing: 8) {
                    Button { self.selectedVendorFilter = nil } label: {
                        Label("All Manufacturers", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    Text(selectedVendorFilter)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 7)
            }

            if scope != .vendors || selectedVendorFilter != nil {
                categoryFilterBar
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search plugins or manufacturers", text: $searchText)
                    .textFieldStyle(.plain)
                .onSubmit(loadChain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(10)
            .background(PlugSpotPalette.card, in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            HStack {
                Text(isLoadingLibrary ? "Reading Ableton Live…" : countSummary)
                Spacer()
                Picker("Plugin view", selection: $displayModeRaw) {
                    Image(systemName: "square.grid.2x2").tag(PluginDisplayMode.cards.rawValue)
                    Image(systemName: "list.bullet").tag(PluginDisplayMode.list.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 76)
                .help("Choose Cards or List view")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            }

            if scope == .favorites, unavailableFavoriteCount > 0 {
                unavailablePluginNotice(count: unavailableFavoriteCount, kind: "favorite")
            } else if scope == .recent, unavailableRecentCount > 0 {
                unavailablePluginNotice(count: unavailableRecentCount, kind: "recent plugin")
            }

            if isLoadingLibrary && plugins.isEmpty {
                Spacer()
                ProgressView("Loading plugin catalog…")
                Spacer()
            } else if plugins.isEmpty {
                emptyState(
                    title: "Ableton Live Not Connected",
                    symbol: "waveform.path",
                    detail: status
                )
            } else if scope == .vendors && selectedVendorFilter == nil {
                if filteredVendorOptions.isEmpty {
                    emptyState(title: "No Manufacturers Found", symbol: "building.2", detail: "Try a different search.")
                } else {
                    vendorResultsView
                }
            } else if filteredFamilies.isEmpty {
                emptyState(
                    title: "No Results",
                    symbol: "magnifyingglass",
                    detail: "No plugins found for “\(searchText)”."
                )
            } else {
                pluginResultsView
            }
            }

            Group {
                if let family = selectedFamily, family.variants.count > 1 {
                    HStack {
                        Text("Channel Variant")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Channel", selection: variantSelection(for: family)) {
                            ForEach(family.variants) { variant in
                                Text(channelLabel(for: variant)).tag(variant.id)
                            }
                        }
                        .frame(maxWidth: 210)
                        .help("Choose channel variant")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }

                if !chainQueue.isEmpty {
                    chainBuilder
                }
            }

            if let localStoreError {
                Text(localStoreError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            Divider()

            HStack(spacing: 12) {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(isError ? .red : .secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isConnectionUnavailable {
                    Button(role: .destructive) {
                        requestPlugSpotQuit()
                    } label: {
                        Label("Quit BubblePlug", systemImage: "power")
                    }
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .help("Quit BubblePlug")
                }
            }
            .padding(12)
            }
        }
        .task {
            loadLocalState()
            registerGlobalHotKey()
            if !didInitializeWindow {
                didInitializeWindow = true
                if let cachedPlugins = try? JSONDecoder().decode([PluginItem].self, from: cachedCatalogJSON),
                   !cachedPlugins.isEmpty,
                   isSupportedLiveVersion(cachedLiveVersion) {
                    plugins = cachedPlugins
                    catalogFamilies = PluginFamily.group(cachedPlugins)
                    liveVersion = cachedLiveVersion
                    if scannerModification(for: cachedLiveVersion) <= cachedScannerModification {
                        prepareArtworkForCatalog(version: cachedLiveVersion)
                    }
                    isLiveVersionSupported = true
                    status = "Using saved Ableton Live catalog · \(catalogFamilies.count) plugins. Refresh to scan Live."
                    readAbletonExportResult()
                } else {
                    refreshLibrary()
                }
            }
            startConnectionMonitor()
        }
        .onDisappear {
            connectionMonitor?.cancel()
            imageProgressPanel.hide()
        }
        .onChange(of: artworkStore.isCapturingFirstRunImages) { _ in updateImageProgressPanel() }
        .onChange(of: artworkStore.captureProgress) { _ in updateImageProgressPanel() }
        .onChange(of: artworkStore.captureCurrentPlugin) { _ in updateImageProgressPanel() }
        .onChange(of: artworkStore.isPreparing) { _ in updateImageProgressPanel() }
        .onChange(of: artworkStore.preparationProgress) { _ in updateImageProgressPanel() }
        .sheet(isPresented: $isCategoryManagerPresented) {
            CategoryManagerView(categories: categories) { updated in
                saveCategories(updated)
            }
        }
        .sheet(isPresented: $isSettingsPresented) { settingsSheet }
        .sheet(isPresented: $isMissingArtworkPresented) { missingArtworkSheet }
        .sheet(isPresented: $isAboutPresented) { AboutBubblePlugView() }
        .confirmationDialog(
            "Replace Ableton Collections?",
            isPresented: $showAbletonExportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Export and Restart Ableton Live", role: .destructive, action: confirmAbletonExport)
            Button("Cancel", role: .cancel) { clearAbletonExportDraft() }
        } message: {
            Text(abletonExportConfirmationMessage)
        }
        .alert("Ableton Export Stopped", isPresented: $showAbletonExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(abletonExportError)
        }
        .background {
            PlugSpotWindowAccessor { window in
                configureWindowControls(window)
            }
            .frame(width: 0, height: 0)
        }
        .modifier(BubblePlugSurface())
    }

    private var settingsSheet: some View {
        PlugSpotSettingsView(
            bubbleScale: $bubbleScale,
            bubbleTransparency: $bubbleTransparency,
            bubblePositionLocked: $bubblePositionLocked,
            shortcutKeyCode: $shortcutKeyCode,
            shortcutModifiers: $shortcutModifiers,
            shortcutLabel: $shortcutLabel,
            shortcutStatus: $shortcutStatus,
            imageStartupMode: $imageStartupMode,
            imageScanIsRunning: artworkStore.isPreparing || artworkStore.isCapturingFirstRunImages,
            missingImageCount: artworkStore.missingPluginImageCount,
            onLoadAllImages: loadAllPluginImages,
            onRecordingChanged: { isRecording in
                if isRecording { globalHotKeyController?.unregister() }
                else { registerGlobalHotKey() }
            },
            onShortcutChanged: registerGlobalHotKey,
            onBubbleChanged: {
                bubbleController.updateAppearance(scale: bubbleScale, transparency: bubbleTransparency, positionLocked: bubblePositionLocked)
            },
            onResetBubblePosition: { bubbleController.resetPosition() }
        )
    }

    private var missingArtworkSheet: some View {
        let allPlugins = pluginFamilies
        let allVendors = vendorOptions
        let managedPlugins = allPlugins.filter { artworkStore.hasPluginImage($0.id) == artworkManagerShowsImages }
        let managedVendors = allVendors.filter { artworkStore.hasVendorImage($0.name) == artworkManagerShowsImages }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manage Images").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { isMissingArtworkPresented = false }
            }
            Text("Manage plugin and manufacturer images. Images you assign remain available after rescanning plugins.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Image status", selection: $artworkManagerShowsImages) {
                Text("Without Images").tag(false)
                Text("With Images").tag(true)
            }
            .pickerStyle(.segmented)
            Text(artworkManagerShowsImages
                 ? "Images available to replace · \(managedPlugins.count) plugins · \(managedVendors.count) manufacturers"
                 : "Images to add manually · \(managedPlugins.count) plugins · \(managedVendors.count) manufacturers")
                .font(.caption.weight(.medium))
            List {
                Section("Manufacturers") {
                    ForEach(managedVendors) { vendor in
                        HStack {
                            vendorArtwork(vendor.name, width: 64, height: 42)
                            Text(vendor.name)
                            Spacer()
                            Button(artworkManagerShowsImages ? "Replace Image…" : "Load Image…") { chooseArtwork(vendor: vendor.name) }
                        }
                        .task(id: "\(vendor.id)|\(liveVersion ?? "")|\(artworkStore.artworkRevision)") {
                            guard let liveVersion else { return }
                            let candidates = allPlugins
                                .filter { normalizedText($0.vendor) == normalizedText(vendor.name) }
                                .flatMap(\.variants)
                            artworkStore.requestVendorImage(vendor: vendor.name, plugins: candidates, liveVersion: liveVersion)
                        }
                    }
                }
                Section("Plugins") {
                    ForEach(managedPlugins) { family in
                        HStack {
                            pluginArtwork(family, width: 52, height: 38)
                                .frame(width: 52, height: 38)
                            Text(family.name)
                            Text(family.vendor).foregroundStyle(.secondary)
                            Spacer()
                            Button(artworkManagerShowsImages ? "Replace Image…" : "Load Image…") { chooseArtwork(pluginID: family.id) }
                        }
                        .task(id: "\(family.id)|\(artworkStore.artworkRevision)") {
                            guard let liveVersion else { return }
                            artworkStore.requestPluginImage(for: family.preferredVariant, familyID: family.id, liveVersion: liveVersion)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 700, height: 540)
        .modifier(BubblePlugSurface())
    }

    private func chooseArtwork(pluginID: String? = nil, vendor: String? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if !artworkStore.setCustomImage(url, pluginID: pluginID, vendor: vendor) {
                status = "Could not load that image. Choose a supported image file."
                isError = true
            }
        }
    }

    private func prepareArtworkForCatalog(version: String) {
        configureScreenRecordingPermissionPresentation()
        artworkStore.prepare(
            plugins: catalogFamilies.map { ($0.id, $0.preferredVariant) },
            liveVersion: version,
            using: library,
            cachedOnly: imageStartupMode != "scan",
            autoCapture: imageStartupMode == "scan"
        )
    }

    private func loadAllPluginImages() {
        guard let liveVersion, !catalogFamilies.isEmpty,
              !artworkStore.isPreparing, !artworkStore.isCapturingFirstRunImages else { return }
        configureScreenRecordingPermissionPresentation()
        imageStartupMode = "scan"
        let entries = catalogFamilies.map { ($0.id, $0.preferredVariant) }
        if artworkStore.missingPluginImageCount == catalogFamilies.count {
            artworkStore.prepare(plugins: entries, liveVersion: liveVersion, force: true, using: library)
        } else {
            artworkStore.retryFirstRunImageCapture(plugins: entries, library: library)
        }
    }

    private func configureScreenRecordingPermissionPresentation() {
        let controller = bubbleController
        let progressPanel = imageProgressPanel
        artworkStore.willRequestScreenRecordingPermission = {
            progressPanel.suspendForSystemPermissionPrompt()
            controller.prepareForSystemPermissionPrompt()
        }
        artworkStore.didRequestScreenRecordingPermission = { granted in
            if granted {
                progressPanel.resumeAfterSystemPermissionPrompt()
            }
            controller.finishSystemPermissionPrompt(granted: granted)
        }
    }

    private func updateImageProgressPanel() {
        imageProgressPanel.update(
            active: artworkStore.isCapturingFirstRunImages || artworkStore.isPreparing,
            progress: artworkStore.isCapturingFirstRunImages ? artworkStore.captureProgress : artworkStore.preparationProgress,
            pluginName: artworkStore.isPreparing ? "Preparing plugin images…" : artworkStore.captureCurrentPlugin
        )
    }

    @ViewBuilder
    private var pluginResultsView: some View {
        if displayMode == .list {
                List(filteredFamilies) { family in
                    HStack(spacing: 10) {
                        pluginArtwork(family, width: 54, height: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(family.name)
                                .font(.body)
                                .lineLimit(1)
                            Text(family.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let labels = labelsByPlugin[family.id], !labels.isEmpty {
                                HStack(spacing: 5) {
                                    ForEach(labels) { label in
                                        HStack(spacing: 3) {
                                            Circle().fill(collectionColor(label.colorIndex ?? 2)).frame(width: 6, height: 6)
                                            Text(label.name)
                                        }
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        Button {
                            toggleFavorite(family)
                        } label: {
                            Image(systemName: favoriteIDs.contains(family.id) ? "star.fill" : "star")
                                .foregroundStyle(favoriteIDs.contains(family.id) ? .yellow : .secondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(favoriteIDs.contains(family.id) ? "Remove from Favorites" : "Add to Favorites")
                    }
                    .task(id: "\(family.id)|\(liveVersion ?? "")|\(artworkStore.artworkRevision)") {
                        guard let liveVersion else { return }
                        artworkStore.requestPluginImage(for: family.preferredVariant, familyID: family.id, liveVersion: liveVersion)
                    }
                    .tag(family.id)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .gesture(TapGesture(count: 2).exclusively(before: TapGesture(count: 1)).onEnded { result in
                        switch result {
                        case .first: loadPlugin(family.preferredVariant, family: family)
                        case .second: selectAndQueue(family)
                        }
                    })
                    .contextMenu {
                        Button("Load \(family.name)") {
                            selectedFamilyID = family.id
                            selectedVariantID = family.preferredVariant.id
                            loadPlugin(family.preferredVariant, family: family)
                        }
                        if !categories.isEmpty {
                            Menu("Categories") {
                                ForEach(categories) { category in
                                    Button {
                                        toggleCategory(category, family: family)
                                    } label: {
                                        Label(category.name, systemImage: hasCategory(category, family: family) ? "checkmark.circle.fill" : "circle")
                                    }
                                }
                            }
                        }
                        Button("Manage Categories…") { isCategoryManagerPresented = true }
                    }
                }
                .listStyle(.inset)
            .scrollContentBackground(.hidden)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    ForEach(filteredFamilies) { family in
                        pluginCard(family)
                    }
                }
                .padding(12)
            }
        }
    }

    private var displayMode: PluginDisplayMode {
        PluginDisplayMode(rawValue: displayModeRaw) ?? .list
    }

    private func pluginCard(_ family: PluginFamily) -> some View {
        let isSelected = selectedFamilyID == family.id
        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                pluginArtwork(family, width: 152, height: 78)
                LinearGradient(colors: [.clear, PlugSpotPalette.card.opacity(0.92)], startPoint: .center, endPoint: .bottom)
                Text(family.vendor.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .padding(.leading, 8)
                    .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PLUGIN")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(PlugSpotPalette.cyan.opacity(0.9))
                    Text(family.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button {
                    toggleFavorite(family)
                } label: {
                    Image(systemName: favoriteIDs.contains(family.id) ? "star.fill" : "star")
                        .foregroundStyle(favoriteIDs.contains(family.id) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(favoriteIDs.contains(family.id) ? "Remove from Favorites" : "Add to Favorites")
            }
            Text(family.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let labels = labelsByPlugin[family.id], !labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(labels.prefix(3)) { label in
                        HStack(spacing: 3) {
                            Circle().fill(collectionColor(label.colorIndex ?? 2)).frame(width: 7, height: 7)
                            Text(label.name).lineLimit(1)
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 174, alignment: .topLeading)
        .background(isSelected ? PlugSpotPalette.selectedCard : PlugSpotPalette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(PlugSpotPalette.iridescence.opacity(isSelected ? 0.95 : 0.18), lineWidth: isSelected ? 2 : 1))
        .shadow(color: isSelected ? PlugSpotPalette.cyan.opacity(0.12) : .clear, radius: 12, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .gesture(
            TapGesture(count: 2)
                .exclusively(before: TapGesture(count: 1))
                .onEnded { result in
                    switch result {
                    case .first:
                        loadPlugin(family.preferredVariant, family: family)
                    case .second:
                        selectAndQueue(family)
                    }
                }
        )
        .contextMenu {
            Button("Load \(family.name)") {
                selectedFamilyID = family.id
                selectedVariantID = family.preferredVariant.id
                loadPlugin(family.preferredVariant, family: family)
            }
            if !categories.isEmpty {
                Menu("Categories") {
                    ForEach(categories) { category in
                        Button {
                            toggleCategory(category, family: family)
                        } label: {
                            Label(category.name, systemImage: hasCategory(category, family: family) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
            }
        }
        .task(id: "\(family.id)|\(liveVersion ?? "")|\(artworkStore.artworkRevision)") {
            guard let liveVersion else { return }
            artworkStore.requestPluginImage(for: family.preferredVariant, familyID: family.id, liveVersion: liveVersion)
        }
    }

    private func pluginArtwork(_ family: PluginFamily, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let image = artworkStore.pluginImages[family.id] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                BubbleMonogram(initials: monogram(for: family.name), width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("\(family.name) artwork")
    }

    private var chainBuilder: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CHAIN BUILDER")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(PlugSpotPalette.cyan)
                    Text("\(chainQueue.count) \(chainQueue.count == 1 ? "plugin" : "plugins") ready to insert")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.86))
                }
                Spacer(minLength: 4)
            }
            HStack(spacing: 8) {
                Button {
                    chainQueue.removeAll()
                    selectedQueuedPluginID = nil
                    activeChainSetID = nil
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingChain || chainQueue.isEmpty)

                Button(activeChainSetID == nil ? "Save Set" : "Save Changes") { saveCurrentChainSet() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLoadingChain || chainQueue.isEmpty)

                Spacer(minLength: 4)

                Button(isLoadingChain ? "Loading…" : "Load Chain") { loadChain() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLoadingChain || chainQueue.isEmpty)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(chainQueue.enumerated()), id: \.element.id) { index, entry in
                        let family = pluginFamilies.first(where: { $0.id == entry.familyID })
                        let isSelected = selectedQueuedPluginID == entry.id
                        VStack(alignment: .leading, spacing: 4) {
                            if let family {
                                pluginArtwork(family, width: 112, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Text(family?.name ?? "Unavailable plugin")
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: 112, alignment: .leading)
                            if let family {
                                Text(family.variants.first(where: { $0.id == entry.pluginID }).map(channelLabel(for:)) ?? "Unavailable")
                                    .font(.caption2)
                                    .foregroundStyle(PlugSpotPalette.cyan)
                            }
                            HStack(spacing: 5) {
                                Image(systemName: "line.3.horizontal")
                                    .help("Drag to reorder")
                                Spacer()
                                Button {
                                    chainQueue.remove(at: index)
                                    if selectedQueuedPluginID == entry.id { selectedQueuedPluginID = nil }
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .disabled(isLoadingChain)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(7)
                        .background(PlugSpotPalette.chainTile, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isSelected ? PlugSpotPalette.cyan : PlugSpotPalette.edge, lineWidth: isSelected ? 2 : 1))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                        .onTapGesture { selectedQueuedPluginID = entry.id }
                        .onDrag { NSItemProvider(object: entry.id.uuidString as NSString) }
                        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                            guard !isLoadingChain, let provider = providers.first else { return false }
                            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                                guard let text = object as? String, let sourceID = UUID(uuidString: text) else { return }
                                Task { @MainActor in moveQueueItem(id: sourceID, onto: entry.id) }
                            }
                            return true
                        }
                        .overlay(alignment: .trailing) {
                            if index < chainQueue.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(PlugSpotPalette.cyan)
                                    .offset(x: 10)
                            }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
            if let selectedQueuedPluginID,
               let selectedIndex = chainQueue.firstIndex(where: { $0.id == selectedQueuedPluginID }),
               let family = pluginFamilies.first(where: { $0.id == chainQueue[selectedIndex].familyID }),
               family.variants.count > 1 {
                HStack {
                    Text("Selected plugin: \(family.name)")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Picker("Channel", selection: Binding(
                        get: { chainQueue[selectedIndex].pluginID },
                        set: { chainQueue[selectedIndex].pluginID = $0 }
                    )) {
                        ForEach(family.variants) { variant in
                            Text(channelLabel(for: variant)).tag(variant.id)
                        }
                    }
                    .frame(width: 180)
                    .disabled(isLoadingChain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PlugSpotPalette.chainShelf)
        .overlay(alignment: .top) { Rectangle().fill(PlugSpotPalette.iridescence).frame(height: 1).opacity(0.55) }
    }

    private var chainSetsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CHAIN SETS").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(PlugSpotPalette.cyan)
                    Text("Save plugin chains for reuse").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Button {
                saveCurrentChainSet()
            } label: {
                Label(activeChainSetID == nil ? "Save Current Chain" : "Save Chain Changes", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(chainQueue.isEmpty)
            .help(chainQueue.isEmpty ? "Add plugins to the chain before saving it" : "Save the current plugin chain as a reusable Chain Set")
            if !chainQueue.isEmpty {
                Label("Current chain: \(chainQueue.count) plugins. Reorder or remove them below, then save.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if chainSets.isEmpty {
                emptyState(title: "No Chain Sets Yet", symbol: "point.3.connected.trianglepath.dotted", detail: "Build a chain in the plugin list, then save it here.")
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(chainSets) { set in
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    if activeChainSetID == set.id { activeChainSetID = nil }
                                    else { loadSavedChainSet(set) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(set.name).font(.headline).lineLimit(1)
                                            Text("\(set.plugins.count) \(set.plugins.count == 1 ? "plugin" : "plugins") · Click to load")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: activeChainSetID == set.id ? "chevron.up" : "chevron.down")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                HStack(spacing: 7) {
                                    Button { exportChainSet(set) } label: {
                                        Label("Export .adg", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.bordered)
                                    .help("Export this Chain Set as an Ableton rack preset")
                                    Button { loadSavedChainSet(set); editingChainSetID = set.id; editingChainSetName = set.name } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .buttonStyle(.bordered)
                                    Button(role: .destructive) { deleteChainSet(set) } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                    Spacer(minLength: 0)
                                }
                                if activeChainSetID == set.id {
                                    if editingChainSetID == set.id {
                                        HStack {
                                            TextField("Chain Set name", text: $editingChainSetName)
                                                .textFieldStyle(.roundedBorder)
                                            Button("Save Name") { renameChainSet(set) }
                                            Button("Cancel") { editingChainSetID = nil }
                                        }
                                    }
                                    ForEach(Array(set.plugins.enumerated()), id: \.offset) { index, plugin in
                                        HStack(spacing: 8) {
                                            Text("\(index + 1).").foregroundStyle(.secondary)
                                            if let family = pluginFamilies.first(where: { $0.id == plugin.familyID }) {
                                                pluginArtwork(family, width: 54, height: 32)
                                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                            }
                                            Text(plugin.name).lineLimit(1)
                                            Spacer()
                                            Text(plugin.format).font(.caption2).foregroundStyle(.secondary)
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                            .padding(12)
                            .background(activeChainSetID == set.id ? PlugSpotPalette.selectedCard : PlugSpotPalette.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(PlugSpotPalette.edge, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .onAppear(perform: loadChainSets)
    }

    private func saveCurrentChainSet() {
        guard let localStore, !chainQueue.isEmpty else { return }
        let name: String
        if let existing = chainSets.first(where: { $0.id == activeChainSetID }) {
            name = existing.name
        } else {
            let alert = NSAlert()
            alert.messageText = "Save Chain Set"
            alert.informativeText = "Choose a name for this plugin chain."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            let field = NSTextField(string: "")
            field.placeholderString = "e.g. Vocal Chain"
            field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
            alert.accessoryView = field
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let savedPlugins = chainQueue.compactMap { queued -> StoredChainPlugin? in
            guard let family = pluginFamilies.first(where: { $0.id == queued.familyID }),
                  let plugin = family.variants.first(where: { $0.id == queued.pluginID }) else { return nil }
            return StoredChainPlugin(familyID: family.id, pluginID: plugin.id, name: family.name, vendor: family.vendor, format: plugin.format)
        }
        do {
            let set = StoredChainSet(id: activeChainSetID ?? UUID().uuidString, name: name, plugins: savedPlugins)
            try localStore.saveChainSet(set)
            activeChainSetID = set.id
            loadChainSets()
            status = "Saved Chain Set: \(name)."
            localStoreError = nil
        } catch { localStoreError = error.localizedDescription }
    }

    private func exportChainSet(_ set: StoredChainSet) {
        guard let liveVersion else {
            showChainExportError("Connect to Ableton Live and refresh the plug-in library before exporting this Chain Set.")
            return
        }
        do {
            try AbletonChainExporter.validate(set, liveVersion: liveVersion)
        } catch {
            showChainExportError(error.localizedDescription)
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Ableton Rack Preset"
        panel.nameFieldStringValue = "\(set.name.replacingOccurrences(of: "/", with: "-")).adg"
        panel.allowedContentTypes = [UTType(filenameExtension: "adg") ?? .data]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard let parent = bubbleController.mainWindowForDialogs else {
            showChainExportError("BubblePlug's window is not ready to present the Save dialog. Reopen BubblePlug and try again.")
            return
        }

        // Present Save as a sheet on the expanded panel. A detached modal dialog
        // from this accessory app/non-activating panel can appear without taking
        // keyboard focus, which makes the filename field look editable but ignore input.
        activeExportPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.beginSheetModal(for: parent) { response in
            defer { activeExportPanel = nil }
            guard response == .OK, let destination = panel.url else { return }
            do {
                try AbletonChainExporter.export(set, to: destination, liveVersion: liveVersion)
                status = "Exported \(set.name) as an Ableton .adg rack. Plug-in presets and private state are not included; Live opens each plug-in with its default state."
            } catch {
                status = "Could not export \(set.name): \(error.localizedDescription)"
                showChainExportError(error.localizedDescription)
            }
        }
    }

    private func showChainExportError(_ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Chain Set Export Failed"
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func loadChainSets() {
        do { chainSets = try localStore?.chainSets() ?? []; localStoreError = nil }
        catch { localStoreError = error.localizedDescription }
    }

    private func loadSavedChainSet(_ set: StoredChainSet) {
        activeChainSetID = set.id
        if let liveVersion {
            for item in set.plugins {
                if let family = pluginFamilies.first(where: { $0.id == item.familyID }),
                   let variant = family.variants.first(where: { $0.id == item.pluginID }) {
                    artworkStore.requestPluginImage(for: variant, familyID: family.id, liveVersion: liveVersion)
                }
            }
        }
        let available = set.plugins.filter { pluginID in
            pluginFamilies.contains(where: { family in family.id == pluginID.familyID && family.variants.contains(where: { $0.id == pluginID.pluginID }) })
        }
        chainQueue = available.map { QueuedPlugin(familyID: $0.familyID, pluginID: $0.pluginID) }
        selectedQueuedPluginID = chainQueue.first?.id
        if available.count == set.plugins.count {
            status = "Loaded \(set.name) into the chain builder."
        } else {
            status = "Loaded \(available.count) of \(set.plugins.count) plugins. Some are unavailable in Live."
        }
    }

    private func renameChainSet(_ set: StoredChainSet) {
        do { try localStore?.renameChainSet(id: set.id, name: editingChainSetName); editingChainSetID = nil; loadChainSets() }
        catch { localStoreError = error.localizedDescription }
    }

    private func deleteChainSet(_ set: StoredChainSet) {
        do {
            try localStore?.deleteChainSet(id: set.id)
            if activeChainSetID == set.id { activeChainSetID = nil; chainQueue.removeAll() }
            if editingChainSetID == set.id { editingChainSetID = nil }
            loadChainSets()
        }
        catch { localStoreError = error.localizedDescription }
    }

    private var isLoadingChain: Bool {
        loadingPluginID == "__plugspot_chain__"
    }

    private func selectAndQueue(_ family: PluginFamily) {
        guard !isLoadingChain else { return }
        let variant = family.preferredVariant
        selectedFamilyID = family.id
        selectedVariantID = variant.id
        let queued = QueuedPlugin(familyID: family.id, pluginID: variant.id)
        chainQueue.append(queued)
        selectedQueuedPluginID = queued.id
        status = "Added \(family.name) to the chain."
        isError = false
    }

    private func moveQueueItem(id sourceID: UUID, onto targetID: UUID) {
        guard !isLoadingChain,
              let source = chainQueue.firstIndex(where: { $0.id == sourceID }),
              let target = chainQueue.firstIndex(where: { $0.id == targetID }),
              source != target else { return }
        let item = chainQueue.remove(at: source)
        chainQueue.insert(item, at: target)
        selectedQueuedPluginID = sourceID
    }

    private func loadChain() {
        guard !chainQueue.isEmpty, loadingPluginID == nil else { return }
        let queued = chainQueue
        activeChainSetID = nil
        loadingPluginID = "__plugspot_chain__"
        isError = false
        status = "Loading chain…"
        Task {
            var loadedCount = 0
            for entry in queued {
                guard let family = pluginFamilies.first(where: { $0.id == entry.familyID }),
                      let plugin = family.variants.first(where: { $0.id == entry.pluginID }) else {
                    chainQueue.removeAll { $0.id == entry.id }
                    continue
                }
                do {
                    let result = try await library.loadPlugin(id: plugin.id)
                    artworkStore.captureLivePluginWindowIfNeeded(for: plugin, familyID: family.id)
                    chainQueue.removeAll { $0.id == entry.id }
                    loadedCount += 1
                    status = "Loaded \(family.name) to “\(result.trackName)”."
                    do {
                        try localStore?.recordLoadRequest(id: family.id, name: family.name, vendor: family.vendor, format: plugin.format)
                        localStoreError = nil
                    } catch {
                        // Live already accepted the load. Keep the chain moving
                        // and report a local history write separately so a
                        // retry cannot insert this plug-in twice.
                        localStoreError = error.localizedDescription
                    }
                } catch {
                    status = loadedCount == 0
                        ? "Chain stopped at \(family.name): \(error.localizedDescription)"
                        : "Chain stopped after \(loadedCount) plug-in(s): \(error.localizedDescription)"
                    isError = true
                    break
                }
            }
            loadLocalState()
            if loadedCount > 0 {
                await MainActor.run {
                    bubbleController.finishPluginLoad()
                }
            }
            loadingPluginID = nil
        }
    }

    private var abletonExportConfirmationMessage: String {
        let match = abletonExportPreflight
        let matched = match?.matchedFamilies ?? 0
        let colored = match?.coloredItemsToClear ?? 0
        let total = match?.totalBrowserItems ?? 0
        let variants = match?.mappedDevices ?? 0
        return "This replaces all seven Collection names and clears existing color assignments across Ableton’s entire Browser, including plugins, presets, samples, folders, and other items. PlugSpot will assign its Favorites and categories to \(matched) matched plugin families (\(variants) VST3 variants). The preflight found \(colored) currently colored items out of \(total). Live will quit and reopen. Save your current Live Set if prompted. No files are changed until Live has fully closed; a backup is created before writing."
    }

    private var plugSpotSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PlugSpot", isDirectory: true)
    }

    private func prepareAbletonExport() {
        guard !isPreparingAbletonExport else { return }
        guard isLiveConnected, isLiveVersionSupported, liveVersion == "12.4.2" else {
            if isLiveConnected {
                presentAbletonExportError("This Live version has not passed PlugSpot's compatibility check. Collection export is validated only for Live 12.4.2.")
                return
            }
            presentAbletonExportError("Ableton Live is not connected. Open Live and try again.")
            return
        }
        guard let localStore else {
            presentAbletonExportError("The PlugSpot library is unavailable.")
            return
        }
        isPreparingAbletonExport = true
        status = "Checking Ableton Collection export…"
        Task {
            do {
                let document = try localStore.exportDocument()
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let requestData = try encoder.encode(document)
                let id = UUID().uuidString.lowercased()
                let requestURL = plugSpotSupportDirectory.appendingPathComponent("export-preflight-\(id).json")
                let resultURL = plugSpotSupportDirectory.appendingPathComponent("export-preflight-result-\(id).json")
                try requestData.write(to: requestURL, options: .atomic)
                defer {
                    try? FileManager.default.removeItem(at: requestURL)
                    try? FileManager.default.removeItem(at: resultURL)
                }
                try await runAbletonExportWorker(arguments: ["--preflight", requestURL.path, resultURL.path])
                let preflight = try JSONDecoder().decode(AbletonExportPreflight.self, from: Data(contentsOf: resultURL))
                guard preflight.ok else {
                    throw AbletonExportUIError.message(preflight.error ?? "Ableton export preflight failed.")
                }
                guard preflight.missing.isEmpty else {
                    let names = preflight.missing.prefix(8).map(\.name).joined(separator: ", ")
                    throw AbletonExportUIError.message("Export stopped without changing Ableton. These PlugSpot plugins could not be matched safely: \(names). Check their format and names, then try again.")
                }
                abletonExportDocument = document
                abletonExportPreflight = preflight
                status = "Preflight passed · \(preflight.matchedFamilies) plugin families matched"
                isError = false
                showAbletonExportConfirmation = true
            } catch {
                presentAbletonExportError(error.localizedDescription)
            }
            isPreparingAbletonExport = false
        }
    }

    private func confirmAbletonExport() {
        guard let document = abletonExportDocument else {
            presentAbletonExportError("The export plan expired. Run the preflight again.")
            return
        }
        let pendingURL = plugSpotSupportDirectory.appendingPathComponent("pending-ableton-export.json")
        guard !FileManager.default.fileExists(atPath: pendingURL.path) else {
            presentAbletonExportError("Another Ableton export is already pending. Close or cancel that export before starting a new one.")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(document)
            try data.write(to: pendingURL, options: .atomic)
        } catch {
            presentAbletonExportError("Could not stage the Ableton export: \(error.localizedDescription)")
            return
        }

        Task {
            do {
                try await requestAbletonQuit()
                status = "Waiting for Ableton Live to close before applying the export…"
                isError = false
                for _ in 0..<60 {
                    try? await Task.sleep(for: .seconds(1))
                    if !FileManager.default.fileExists(atPath: pendingURL.path) { return }
                    let socket = plugSpotSupportDirectory.appendingPathComponent("bridge.sock")
                    if !FileManager.default.fileExists(atPath: socket.path) { return }
                }
                try? FileManager.default.removeItem(at: pendingURL)
                status = "Export cancelled because Ableton Live stayed open. No files were changed."
                isError = true
            } catch {
                try? FileManager.default.removeItem(at: pendingURL)
                presentAbletonExportError(error.localizedDescription)
            }
            clearAbletonExportDraft()
        }
    }

    private func requestAbletonQuit() async throws {
        let result = await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application id \"com.ableton.live\" to quit"]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            do {
                try process.run()
                process.waitUntilExit()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                return (process.terminationStatus, String(data: errorData, encoding: .utf8) ?? "")
            } catch {
                return (-1, error.localizedDescription)
            }
        }.value
        guard result.0 == 0 else {
            throw AbletonExportUIError.message("Could not ask Ableton Live to quit: \(result.1.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private func runAbletonExportWorker(arguments: [String]) async throws {
        let worker = plugSpotSupportDirectory.appendingPathComponent("ableton-export-worker.py")
        guard FileManager.default.fileExists(atPath: worker.path) else {
            throw AbletonExportUIError.message("The Ableton export worker is not installed. Run macos/install-launcher.sh and restart Live.")
        }
        let result = await Task.detached(priority: .utility) { () -> (Int32, String) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [worker.path] + arguments
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                return (process.terminationStatus, String(data: errorData, encoding: .utf8) ?? "")
            } catch {
                return (-1, error.localizedDescription)
            }
        }.value
        guard result.0 >= 0 else {
            let detail = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AbletonExportUIError.message(detail.isEmpty ? "Could not start the Ableton export worker." : detail)
        }
    }

    private func readAbletonExportResult() {
        let resultURL = plugSpotSupportDirectory.appendingPathComponent("ableton-export-result.json")
        guard let data = try? Data(contentsOf: resultURL) else { return }
        try? FileManager.default.removeItem(at: resultURL)
        guard let result = try? JSONDecoder().decode(AbletonExportResult.self, from: data) else { return }
        if result.ok {
            status = "Ableton Collections updated · \(result.matchedFamilies ?? 0) plugin families · Backup: \(result.backupDirectory ?? "saved")"
            isError = false
        } else {
            status = result.error ?? "Ableton export stopped. No Collections were changed."
            isError = true
            abletonExportError = status
            showAbletonExportError = true
        }
    }

    private func presentAbletonExportError(_ message: String) {
        abletonExportError = message
        status = message
        isError = true
        showAbletonExportError = true
        clearAbletonExportDraft()
    }

    private func clearAbletonExportDraft() {
        abletonExportDocument = nil
        abletonExportPreflight = nil
    }

    private func startConnectionMonitor() {
        connectionMonitor?.cancel()
        connectionMonitor = Task {
            var consecutiveFailures = 0
            var hasObservedConnection = false
            var hasReportedDisconnect = false
            while !Task.isCancelled {
                do {
                    let response = try await UnixDomainSocketClient().send(BridgeRequest(method: .ping))
                    guard response.ok else {
                        throw AbletonLibraryError.bridge(
                            code: response.error?.code ?? "live_unavailable",
                            message: response.error?.message ?? "Ableton Live is not ready.",
                            retryable: response.error?.retryable ?? true
                        )
                    }
                    consecutiveFailures = 0
                    isLiveConnected = true
                    isConnectionUnavailable = false
                    if !hasObservedConnection {
                        bubbleController.showBubble()
                    }
                    if hasReportedDisconnect {
                        hasReportedDisconnect = false
                        status = "Connection to Ableton Live restored. Refreshing the plugin library…"
                        isError = false
                        refreshLibrary()
                    } else if !hasObservedConnection && !isLoadingLibrary &&
                                (plugins.isEmpty || (liveVersion.map { scannerModification(for: $0) } ?? 0) > cachedScannerModification) {
                        refreshLibrary()
                    }
                    hasObservedConnection = true
                } catch {
                    consecutiveFailures += 1
                    if consecutiveFailures >= 3 {
                        if isLiveConnected {
                            isLiveConnected = false
                            hasReportedDisconnect = true
                        }
                        status = bridgeUnavailableMessage
                        isError = true
                        isConnectionUnavailable = true
                    }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var visibleEntryCount: Int {
        filteredFamilies.reduce(0) { $0 + $1.variants.count }
    }

    @ViewBuilder
    private var categoryFilterBar: some View {
        HStack(spacing: 6) {
            if categories.isEmpty {
                Button("Manage Categories…") { isCategoryManagerPresented = true }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(categories) { category in
                            let isSelected = selectedCategoryFilters.contains(category.name)
                            Button {
                                if isSelected { selectedCategoryFilters.remove(category.name) }
                                else { selectedCategoryFilters.insert(category.name) }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(collectionColor(category.colorIndex)).frame(width: 8, height: 8)
                                    Text(category.name).lineLimit(1)
                                }
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(isSelected ? collectionColor(category.colorIndex).opacity(0.22) : Color.clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(collectionColor(category.colorIndex).opacity(isSelected ? 0.9 : 0.45), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
                if !selectedCategoryFilters.isEmpty {
                    Button("Clear Categories") { selectedCategoryFilters.removeAll() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 7)
    }

    private var vendorOptions: [VendorFilterOption] {
        Dictionary(grouping: pluginFamilies.filter { !$0.vendor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            normalizedText($0.vendor)
        }
        .map { key, families in
            VendorFilterOption(id: key, name: families.map(\.vendor).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.first ?? key, count: families.count)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var filteredVendorOptions: [VendorFilterOption] {
        let query = normalizedText(searchText)
        guard !query.isEmpty else { return vendorOptions }
        return vendorOptions.filter { normalizedText($0.name).localizedStandardContains(query) }
    }

    @ViewBuilder
    private var vendorResultsView: some View {
        if displayMode == .list {
            List(filteredVendorOptions) { option in
                Button { selectVendorFilter(option.name) } label: {
                    HStack(spacing: 10) {
                        vendorArtwork(option.name, width: 56, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name).font(.body)
                            Text("\(option.count) plugins").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .task(id: "\(option.id)|\(liveVersion ?? "")|\(artworkStore.artworkRevision)") {
                    guard let liveVersion else { return }
                    let candidates = pluginFamilies
                        .filter { normalizedText($0.vendor) == normalizedText(option.name) }
                        .flatMap(\.variants)
                    artworkStore.requestVendorImage(vendor: option.name, plugins: candidates, liveVersion: liveVersion)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    ForEach(filteredVendorOptions) { option in
                        Button { selectVendorFilter(option.name) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                vendorArtwork(option.name, width: 94, height: 52)
                                Text(option.name)
                                    .font(.body.weight(.medium))
                                    .lineLimit(2)
                                Text("\(option.count) plugins")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            .padding(10)
                            .background(PlugSpotPalette.card, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(PlugSpotPalette.iridescence.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .task(id: "\(option.id)|\(liveVersion ?? "")|\(artworkStore.artworkRevision)") {
                            guard let liveVersion else { return }
                            let candidates = pluginFamilies
                                .filter { normalizedText($0.vendor) == normalizedText(option.name) }
                                .flatMap(\.variants)
                            artworkStore.requestVendorImage(vendor: option.name, plugins: candidates, liveVersion: liveVersion)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func vendorArtwork(_ vendor: String, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let image = artworkStore.vendorImages[PluginArtworkStore.normalized(vendor)] {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                BubbleMonogram(initials: monogram(for: vendor), width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("\(vendor) logo")
    }

    private func monogram(for value: String) -> String {
        let words = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count > 1 {
            return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
        return String(value.prefix(2)).uppercased()
    }

    private func selectVendorFilter(_ vendor: String?) {
        selectedVendorFilter = vendor
        selectedFamilyID = nil
        selectedVariantID = nil
    }

    private var countSummary: String {
        let scopeLabel: String
        switch scope {
        case .all: scopeLabel = "plugins · \(visibleEntryCount) Live entries"
        case .favorites: scopeLabel = "favorites"
        case .recent: scopeLabel = "recent"
        case .vendors:
            if let selectedVendorFilter { return "\(filteredFamilies.count) plugins · \(selectedVendorFilter)" }
            return "\(filteredVendorOptions.count) manufacturers"
        case .chainSets: scopeLabel = "Chain Sets · \(chainSets.count) saved"
        }
        var qualifiers: [String] = []
        if !selectedCategoryFilters.isEmpty { qualifiers.append("\(selectedCategoryFilters.count) active categories") }
        let suffix = qualifiers.isEmpty ? "" : " · " + qualifiers.joined(separator: " · ")
        return "\(filteredFamilies.count) \(scopeLabel)\(suffix)"
    }

    private func variantSelection(for family: PluginFamily) -> Binding<String> {
        Binding(
            get: {
                family.variants.contains(where: { $0.id == selectedVariantID })
                    ? selectedVariantID!
                    : family.preferredVariant.id
            },
            set: { selectedVariantID = $0 }
        )
    }

    private func emptyState(title: String, symbol: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func unavailablePluginNotice(count: Int, kind: String) -> some View {
        Label(
            "\(count) saved \(kind)\(count == 1 ? " is" : "s are") missing from Live's current catalog. PlugSpot kept the saved data.",
            systemImage: "exclamationmark.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 5)
    }

    private func refreshLibrary() {
        guard !isLoadingLibrary else {
            refreshAfterCurrentLoad = true
            return
        }
        isLoadingLibrary = true
        isLiveVersionSupported = false
        isError = false
        isConnectionUnavailable = false
        status = "Connecting to Ableton Live…"

        Task {
            do {
                let hello = try await library.hello()
                guard let detectedLiveVersion = hello.liveVersion, !detectedLiveVersion.isEmpty else {
                    throw AbletonLibraryError.liveVersionUnavailable
                }
                guard isSupportedLiveVersion(detectedLiveVersion) else {
                    throw AbletonLibraryError.unsupportedLiveVersion(detectedLiveVersion)
                }
                liveVersion = detectedLiveVersion
                isLiveVersionSupported = true
                let refreshedPlugins = try await library.plugins()
                plugins = refreshedPlugins
                catalogFamilies = PluginFamily.group(refreshedPlugins)
                prepareArtworkForCatalog(version: detectedLiveVersion)
                cachedLiveVersion = detectedLiveVersion
                cachedScannerModification = scannerModification(for: detectedLiveVersion)
                if let encodedCatalog = try? JSONEncoder().encode(refreshedPlugins) {
                    cachedCatalogJSON = encodedCatalog
                }
                let availablePluginIDs = Set(refreshedPlugins.map(\.id))
                let unavailableQueuedCount = chainQueue.filter { !availablePluginIDs.contains($0.pluginID) }.count
                chainQueue.removeAll { !availablePluginIDs.contains($0.pluginID) }
                if let selectedVariantID, !refreshedPlugins.contains(where: { $0.id == selectedVariantID }) {
                    self.selectedVariantID = nil
                    self.selectedFamilyID = nil
                }
                if unavailableQueuedCount > 0 {
                    status = "Removed \(unavailableQueuedCount) unavailable plugin(s) from the chain. Favorites and categories remain saved."
                } else {
                    let validationNote = detectedLiveVersion == "12.4.2" ? "" : " · version not fully validated"
                    status = "Connected to Ableton Live \(detectedLiveVersion) · \(catalogFamilies.count) plugins\(validationNote)"
                }
                isError = false
                readAbletonExportResult()
            } catch {
                if let libraryError = error as? AbletonLibraryError,
                   case .unsupportedLiveVersion = libraryError {
                    plugins = []
                    catalogFamilies = []
                    selectedFamilyID = nil
                    selectedVariantID = nil
                    liveVersion = nil
                    isLiveVersionSupported = false
                } else if let libraryError = error as? AbletonLibraryError,
                          case .liveVersionUnavailable = libraryError {
                    plugins = []
                    catalogFamilies = []
                    liveVersion = nil
                    isLiveVersionSupported = false
                }
                isError = true
                status = error.localizedDescription
            }
            isLoadingLibrary = false
            if refreshAfterCurrentLoad {
                refreshAfterCurrentLoad = false
                refreshLibrary()
            }
        }
    }

    @MainActor
    private func configureWindowControls(_ window: NSWindow) {
        let panel = bubbleController.prepareStartupWindow(
            window,
            artworkStore: artworkStore,
            imageProgressPanel: imageProgressPanel
        )
        panel.title = "BubblePlug"
        panel.backgroundColor = NSColor(PlugSpotPalette.canvas)
        panel.styleMask.remove(.closable)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        guard let minimizeButton = panel.standardWindowButton(.miniaturizeButton) else { return }

        let target: PlugSpotWindowButtonTarget
        if let current = windowButtonTarget, current.window === panel {
            target = current
        } else {
            target = PlugSpotWindowButtonTarget(window: panel) { [weak bubbleController] window in
                bubbleController?.show(minimizing: window)
            }
            windowButtonTarget = target
        }
        minimizeButton.target = target
        minimizeButton.action = #selector(PlugSpotWindowButtonTarget.minimizeToBubble(_:))
        minimizeButton.toolTip = "Minimize BubblePlug to its Ableton bubble"
    }

    private func registerGlobalHotKey() {
        if globalHotKeyController == nil {
            let controller = PlugSpotGlobalHotKeyController()
            controller.onPress = { [weak bubbleController] in
                bubbleController?.showMainWindow()
            }
            globalHotKeyController = controller
        }
        let result = globalHotKeyController?.register(
            keyCode: UInt32(shortcutKeyCode),
            modifiers: UInt32(shortcutModifiers)
        ) ?? -1
        shortcutStatus = result == noErr
            ? ""
            : "macOS couldn't register this shortcut (\(result)). Choose another key combination."
    }

    private func loadPlugin(_ plugin: PluginItem, family: PluginFamily) {
        guard loadingPluginID == nil else { return }
        activeChainSetID = nil
        loadingPluginID = plugin.id
        isError = false
        status = "Loading \(family.name) (\(channelLabel(for: plugin)))…"

        Task {
            do {
                let result = try await library.loadPlugin(id: plugin.id)
                artworkStore.captureLivePluginWindowIfNeeded(for: plugin, familyID: family.id)
                do {
                    try localStore?.recordLoadRequest(id: family.id, name: family.name, vendor: family.vendor, format: plugin.format)
                    loadLocalState()
                } catch {
                    localStoreError = error.localizedDescription
                }
                status = "Load request for \(family.name) sent to “\(result.trackName)”. Check Live."
                chainQueue.removeAll { $0.pluginID == plugin.id }
                await MainActor.run {
                    bubbleController.finishPluginLoad()
                }
            } catch {
                isError = true
                status = error.localizedDescription
            }
            loadingPluginID = nil
        }
    }

    private func channelLabel(for plugin: PluginItem) -> String {
        PluginFamily.channelFormat(for: plugin.name)
    }

    private func loadLocalState() {
        guard let localStore else {
            localStoreError = LocalLibraryStoreError.open("the store is not initialized").localizedDescription
            return
        }
        do {
            favoriteRecords = try localStore.favoriteRecords()
            favoriteIDs = try localStore.favoriteIDs()
            recentRecords = try localStore.recentRecords()
            labelsByPlugin = Dictionary(grouping: try localStore.labels(), by: \.pluginID)
                .mapValues { $0.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
            categories = try localStore.categories()
            localStoreError = nil
        } catch {
            localStoreError = error.localizedDescription
        }
    }

    private func importAbletonOrganization() {
        guard !isImportingOrganization else { return }
        guard localStore != nil else {
            localStoreError = "The local library is unavailable."
            return
        }
        isImportingOrganization = true
        status = "Importing Ableton Collections…"
        Task {
            do {
                let imported = try await Task.detached(priority: .utility) {
                    try AbletonOrganizationImporter.read()
                }.value
                let families = pluginFamilies
                var categoryByAbletonIndex: [Int: LocalCategory] = [:]
                var existingCategories = try localStore?.categories() ?? []
                var omittedCategories = 0
                for label in imported.labels where (2...7).contains(label.colorIndex) {
                    if let existing = existingCategories.first(where: { $0.name.caseInsensitiveCompare(label.name) == .orderedSame }) {
                        categoryByAbletonIndex[label.colorIndex] = existing
                        continue
                    }
                    guard existingCategories.count < 6 else {
                        omittedCategories += 1
                        continue
                    }
                    let usedIndexes = Set(existingCategories.map(\.colorIndex))
                    let index = usedIndexes.contains(label.colorIndex)
                        ? (2...7).first(where: { !usedIndexes.contains($0) })
                        : label.colorIndex
                    guard let index else {
                        omittedCategories += 1
                        continue
                    }
                    let category = LocalCategory(name: label.name, colorIndex: index)
                    try localStore?.saveCategory(category)
                    existingCategories.append(category)
                    categoryByAbletonIndex[label.colorIndex] = category
                }
                var matched = 0
                var importedFavorites = 0
                var importedLabels = 0
                for item in imported.plugins {
                    guard let family = matchFamily(name: item.name, vendor: item.vendor, in: families) else { continue }
                    matched += 1
                    for collection in item.collections {
                        if collection.colorIndex == 1 {
                            try localStore?.setFavorite(
                                id: family.id,
                                name: family.name,
                                vendor: family.vendor,
                                format: family.variants.first?.format ?? "VST3",
                                isFavorite: true
                            )
                            importedFavorites += 1
                        } else {
                            guard let category = categoryByAbletonIndex[collection.colorIndex] else { continue }
                            try localStore?.addLabel(LocalPluginLabel(pluginID: family.id, name: category.name, kind: "category", source: "ableton", colorIndex: category.colorIndex, pluginName: family.name, vendor: family.vendor, format: family.variants.first?.format ?? "VST3"))
                            importedLabels += 1
                        }
                    }
                }
                loadLocalState()
                status = "Imported Ableton Collections: \(importedFavorites) favorites and \(importedLabels) category assignments across \(matched) matched plugins."
                if omittedCategories > 0 {
                    status += " \(omittedCategories) categories were skipped because all six slots are in use."
                }
                isError = false
            } catch {
                status = error.localizedDescription
                isError = true
            }
            isImportingOrganization = false
        }
    }

    private func matchFamily(name: String, vendor: String, in families: [PluginFamily]) -> PluginFamily? {
        let normalizedName = normalizedFamilyName(name)
        let nameMatches = families.filter { normalizedFamilyName($0.name) == normalizedName }
        guard !vendor.isEmpty else { return nameMatches.count == 1 ? nameMatches[0] : nil }
        let normalizedVendor = normalizedText(vendor)
        let vendorMatches = nameMatches.filter { normalizedText($0.vendor) == normalizedVendor }
        return vendorMatches.first
    }

    private func normalizedFamilyName(_ name: String) -> String {
        normalizedText(PluginFamily.familyBaseName(for: name))
    }

    private func normalizedText(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func importPlugSpotLibrary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import BubblePlug Library"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let localStore else { throw LocalLibraryStoreError.open("the local library is unavailable") }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(PlugSpotLibraryDocument.self, from: Data(contentsOf: url))
            try localStore.importDocument(document)
            loadLocalState()
            status = "PlugSpot library merged. Favorites, categories, and recent history were combined."
            isError = false
        } catch {
            status = "Could not import file: \(error.localizedDescription)"
            isError = true
        }
    }

    private func exportPlugSpotLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "plugspot-library.json"
        panel.title = "Export BubblePlug Library"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let localStore else { throw LocalLibraryStoreError.open("the store is unavailable") }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(localStore.exportDocument()).write(to: url, options: .atomic)
            status = "Library exported to \(url.lastPathComponent)."
            isError = false
        } catch {
            status = "Could not export library: \(error.localizedDescription)"
            isError = true
        }
    }

    private func hasCategory(_ category: LocalCategory, family: PluginFamily) -> Bool {
        labelsByPlugin[family.id]?.contains(where: { $0.kind == "category" && $0.name.caseInsensitiveCompare(category.name) == .orderedSame }) ?? false
    }

    private func toggleCategory(_ category: LocalCategory, family: PluginFamily) {
        do {
            try localStore?.setCategory(category, pluginID: family.id, pluginName: family.name, vendor: family.vendor, format: family.variants.first?.format ?? "VST3", assigned: !hasCategory(category, family: family))
            loadLocalState()
            status = hasCategory(category, family: family)
                ? "Category “\(category.name)” added to \(family.name)."
                : "Category “\(category.name)” removed from \(family.name)."
            isError = false
        } catch { status = error.localizedDescription; isError = true }
    }

    private func saveCategories(_ updated: [LocalCategory]) {
        guard let localStore else { return }
        do {
            let old = try localStore.categories()
            let updatedIDs = Set(updated.map(\.id))
            for category in old where !updatedIDs.contains(category.id) { try localStore.deleteCategory(category) }
            for category in updated {
                let oldName = old.first(where: { $0.id == category.id })?.name
                try localStore.saveCategory(category, replacing: oldName)
            }
            loadLocalState()
            status = "PlugSpot categories updated."
            isError = false
        } catch { status = error.localizedDescription; isError = true }
    }

    private func collectionColor(_ index: Int) -> Color {
        switch index {
        case 1: return Color(red: 0.93, green: 0.30, blue: 0.34)
        case 2: return Color(red: 0.96, green: 0.49, blue: 0.24)
        case 3: return Color(red: 0.95, green: 0.73, blue: 0.22)
        case 4: return Color(red: 0.43, green: 0.72, blue: 0.31)
        case 5: return Color(red: 0.20, green: 0.72, blue: 0.65)
        case 6: return Color(red: 0.27, green: 0.52, blue: 0.88)
        default: return Color(red: 0.62, green: 0.38, blue: 0.82)
        }
    }

    private func toggleFavorite(_ family: PluginFamily) {
        guard let localStore else {
            localStoreError = "The local library is unavailable."
            return
        }
        let shouldFavorite = !favoriteIDs.contains(family.id)
        do {
            try localStore.setFavorite(
                id: family.id,
                name: family.name,
                vendor: family.vendor,
                format: family.variants.first?.format ?? "VST3",
                isFavorite: shouldFavorite
            )
            if shouldFavorite {
                favoriteIDs.insert(family.id)
                status = "\(family.name) added to Favorites."
            } else {
                favoriteIDs.remove(family.id)
                status = "\(family.name) removed from Favorites."
            }
            localStoreError = nil
        } catch {
            localStoreError = error.localizedDescription
        }
    }
}

private struct QueuedPlugin: Identifiable {
    let id = UUID()
    let familyID: String
    var pluginID: String
}

private struct PlugSpotWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> PlugSpotWindowObservingView {
        let view = PlugSpotWindowObservingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: PlugSpotWindowObservingView, context: Context) {
        nsView.onWindow = onWindow
        if let window = nsView.window {
            nsView.notifyWindowIfNeeded(window)
        }
    }
}

private final class PlugSpotWindowObservingView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private var scheduledWindowID: ObjectIdentifier?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduledWindowID = nil
        if let window {
            notifyWindowIfNeeded(window)
        }
    }

    func notifyWindowIfNeeded(_ window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        guard scheduledWindowID != windowID else { return }
        scheduledWindowID = windowID
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            self.onWindow?(window)
        }
    }
}

@MainActor
private final class PlugSpotWindowButtonTarget: NSObject {
    weak var window: NSWindow?
    private let minimize: (NSWindow) -> Void

    init(window: NSWindow, minimize: @escaping (NSWindow) -> Void) {
        self.window = window
        self.minimize = minimize
    }

    @objc func minimizeToBubble(_ sender: Any?) {
        guard let window else { return }
        minimize(window)
    }
}

@MainActor
private final class ImageCaptureProgressPanel {
    private var panel: NSPanel?
    private var isActive = false
    private var isSuspendedForSystemPrompt = false
    private var activationObserver: NSObjectProtocol?

    init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in controller.refreshVisibility() }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func update(active: Bool, progress: Double, pluginName: String) {
        isActive = active
        guard active else { hide(); return }
        if panel == nil {
            let created = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 82),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = true
            created.level = .floating
            created.hidesOnDeactivate = false
            created.collectionBehavior = [.fullScreenAuxiliary]
            panel = created
        }
        panel?.contentView = NSHostingView(rootView: ImageCaptureProgressView(progress: progress, pluginName: pluginName))
        if let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main,
           let panel {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 14))
        }
        refreshVisibility()
    }

    func hide() {
        isActive = false
        panel?.orderOut(nil)
    }

    func suspendForSystemPermissionPrompt() {
        isSuspendedForSystemPrompt = true
        panel?.orderOut(nil)
    }

    func resumeAfterSystemPermissionPrompt() {
        isSuspendedForSystemPrompt = false
        refreshVisibility()
    }

    private func refreshVisibility() {
        guard isActive, !isSuspendedForSystemPrompt, let panel else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundle = frontmost?.bundleIdentifier ?? ""
        let name = frontmost?.localizedName?.lowercased() ?? ""
        if bundle == "com.plugspot.app" || bundle.hasPrefix("com.ableton.live") ||
            name.contains("ableton live") || name.contains("editorhost") || name.contains("bubbleplugcapture") {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }
}

private struct ImageCaptureProgressView: View {
    let progress: Double
    let pluginName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Loading plugin images")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .monospacedDigit()
                    .font(.system(size: 12, weight: .medium))
            }
            ProgressView(value: progress)
                .tint(PlugSpotPalette.cyan)
            Text(pluginName.isEmpty ? "Preparing…" : pluginName)
                .lineLimit(1)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .frame(width: 380, height: 82)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.05, green: 0.08, blue: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(PlugSpotPalette.cyan.opacity(0.65)))
    }
}

private final class PlugSpotBubbleController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var mainWindow: NSPanel?
    var mainWindowForDialogs: NSWindow? { mainWindow }
    private weak var trackedScreen: NSScreen?
    private var trackingTimer: Timer?
    private var appActivationObserver: NSObjectProtocol?
    private var mainWindowFocusObserver: NSObjectProtocol?
    private var mainWindowResizeObserver: NSObjectProtocol?
    private var lastLiveWindowFrame: NSRect?
    private var isMovingProgrammatically = false
    private var isDraggingBubble = false
    private let sizePreferenceKey = "plugspot.bubble.scale"
    private let transparencyPreferenceKey = "plugspot.bubble.transparency"
    private let positionLockedPreferenceKey = "plugspot.bubble.position.locked"
    private let positionSavedPreferenceKey = "plugspot.bubble.position.saved"
    private let positionXPreferenceKey = "plugspot.bubble.position.x"
    private let positionYPreferenceKey = "plugspot.bubble.position.y"
    private let windowWidthPreferenceKey = "plugspot.window.width"
    private let windowHeightPreferenceKey = "plugspot.window.height"

    override init() {
        super.init()
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if Self.isAbleton(application) {
                self.handleLiveActivation()
            } else if application.bundleIdentifier == Bundle.main.bundleIdentifier {
                // The main BubblePlug window is the expanded state. Hide only
                // the bubble when the user activates BubblePlug itself.
                self.panel?.orderOut(nil)
            } else {
                self.hideBubbleForOtherApplication()
            }
        }
    }

    deinit {
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
        }
        if let mainWindowFocusObserver {
            NotificationCenter.default.removeObserver(mainWindowFocusObserver)
        }
        if let mainWindowResizeObserver {
            NotificationCenter.default.removeObserver(mainWindowResizeObserver)
        }
    }

    private static func isAbleton(_ application: NSRunningApplication?) -> Bool {
        application?.bundleIdentifier?.localizedCaseInsensitiveContains("com.ableton.live") == true
    }

    private func handleLiveActivation() {
        guard let mainWindow else { return }
        show(minimizing: mainWindow)
    }

    func prepareForSystemPermissionPrompt() {
        // The expanded window can be promoted above normal macOS dialogs while
        // Live is frontmost. Lower it and remove the bubble so the Screen
        // Recording authorization prompt can appear unobstructed.
        panel?.orderOut(nil)
        mainWindow?.level = .normal
        mainWindow?.isFloatingPanel = false
    }

    func finishSystemPermissionPrompt(granted: Bool) {
        guard granted, let mainWindow else { return }
        let abletonIsFrontmost = Self.isAbleton(NSWorkspace.shared.frontmostApplication)
        mainWindow.level = abletonIsFrontmost ? .screenSaver : .normal
        mainWindow.isFloatingPanel = abletonIsFrontmost
    }

    @discardableResult
    func prepareStartupWindow(
        _ window: NSWindow,
        artworkStore: PluginArtworkStore,
        imageProgressPanel: ImageCaptureProgressPanel
    ) -> NSPanel {
        if let mainWindow { return mainWindow }

        let sourceFrame = window.frame
        let expanded = NSPanel(
            contentRect: sourceFrame,
            styleMask: [.titled, .resizable, .miniaturizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        expanded.title = "BubblePlug"
        expanded.isFloatingPanel = true
        expanded.hidesOnDeactivate = false
        expanded.backgroundColor = NSColor(PlugSpotPalette.canvas)
        expanded.isReleasedWhenClosed = false
        expanded.delegate = self
        expanded.minSize = NSSize(width: 440, height: 520)
        expanded.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if #available(macOS 26.0, *) {
            expanded.collectionBehavior.insert(.canJoinAllApplications)
        }
        expanded.level = .normal

        // A SwiftUI hosting view stops drawing reliably when detached from its
        // scene window. Give the non-activating panel its own root view instead
        // of moving the scene's NSHostingView between windows.
        mainWindow = expanded
        window.contentView = nil
        expanded.contentView = NSHostingView(rootView: PlugSpotView(
            bubbleController: self,
            artworkStore: artworkStore,
            imageProgressPanel: imageProgressPanel
        ))
        window.orderOut(nil)

        restoreWindowSize(expanded)
        observeMainWindowFocus(expanded)
        observeMainWindowSize(expanded)
        return expanded
    }

    private func restoreWindowSize(_ window: NSWindow) {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: windowWidthPreferenceKey)
        let height = defaults.double(forKey: windowHeightPreferenceKey)
        guard width >= 440, height >= 520 else { return }
        let visibleSize = (window.screen ?? NSScreen.main)?.visibleFrame.size
        let savedSize = NSSize(
            width: min(CGFloat(width), visibleSize?.width ?? CGFloat(width)),
            height: min(CGFloat(height), visibleSize?.height ?? CGFloat(height))
        )
        window.setContentSize(savedSize)
    }

    private func observeMainWindowSize(_ window: NSWindow) {
        if let mainWindowResizeObserver {
            NotificationCenter.default.removeObserver(mainWindowResizeObserver)
        }
        mainWindowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window, self.mainWindow === window, window.isVisible else { return }
            let size = window.contentRect(forFrameRect: window.frame).size
            let defaults = UserDefaults.standard
            defaults.set(Double(size.width), forKey: self.windowWidthPreferenceKey)
            defaults.set(Double(size.height), forKey: self.windowHeightPreferenceKey)
        }
    }

    private func observeMainWindowFocus(_ window: NSWindow) {
        if let mainWindowFocusObserver {
            NotificationCenter.default.removeObserver(mainWindowFocusObserver)
        }
        mainWindowFocusObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window, self.mainWindow === window else { return }
            // A settings sheet or another BubblePlug-owned window can become
            // key without the user leaving BubblePlug.
            if let keyWindow = NSApp.keyWindow, keyWindow !== window {
                return
            }
            if Self.isAbleton(NSWorkspace.shared.frontmostApplication) {
                self.show(minimizing: window)
            } else {
                self.hideBubbleForOtherApplication()
            }
        }
    }

    private func hideBubbleForOtherApplication() {
        guard !Self.isAbleton(NSWorkspace.shared.frontmostApplication) else { return }
        panel?.orderOut(nil)
        if mainWindow?.isVisible == true {
            mainWindow?.orderOut(nil)
        }
        panel?.level = .normal
        mainWindow?.level = .normal
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    func updateAppearance(scale: Double, transparency: Double, positionLocked: Bool) {
        UserDefaults.standard.set(scale, forKey: sizePreferenceKey)
        UserDefaults.standard.set(transparency, forKey: transparencyPreferenceKey)
        UserDefaults.standard.set(positionLocked, forKey: positionLockedPreferenceKey)
        guard let panel else { return }
        let size = 58 * CGFloat(scale)
        panel.alphaValue = CGFloat(max(0, min(100, 100 - transparency)) / 100)
        panel.isMovableByWindowBackground = false
        panel.contentView = bubbleView(size: size)
        var frame = panel.frame
        frame.size = NSSize(width: size, height: size)
        movePanel(to: frame)
        followLiveWindow()
    }

    func show(minimizing window: NSWindow?) {
        guard let window, let expanded = window as? NSPanel else { return }
        mainWindow = expanded
        let scale = configuredScale
        let size = NSSize(width: 58 * scale, height: 58 * scale)
        let bubble = panel ?? makePanel(size: size)
        panel = bubble
        bubble.alphaValue = CGFloat(max(0, min(100, 100 - configuredTransparency)) / 100)
        let abletonIsFrontmost = Self.isAbleton(NSWorkspace.shared.frontmostApplication)
        // Full-screen Live can cover floating windows. This panel may use the
        // screen-saver level only while Live is frontmost; other-app activation
        // orders both BubblePlug panels out and restores their normal levels.
        bubble.level = abletonIsFrontmost ? .screenSaver : .normal
        bubble.isFloatingPanel = abletonIsFrontmost
        bubble.isMovableByWindowBackground = false
        bubble.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let fallbackScreen = window.screen ?? NSScreen.main
        if let fallbackScreen {
            trackedScreen = fallbackScreen
            movePanel(to: bubbleFrame(size: size, on: fallbackScreen, near: window.frame))
        }
        if abletonIsFrontmost {
            bubble.orderFrontRegardless()
        } else {
            bubble.orderFront(nil)
        }
        window.orderOut(nil)
        followLiveWindow()
        startTracking()
    }

    func finishPluginLoad() {
        guard let mainWindow else { return }
        show(minimizing: mainWindow)
        // Return focus to Live without explicitly raising its main window
        // above the plugin editor that Live just opened.
        if NSApp.isActive {
            NSWorkspace.shared.runningApplications.first(where: { Self.isAbleton($0) })?
                .activate(options: [])
        }
    }

    func showBubble() {
        guard let mainWindow else { return }
        show(minimizing: mainWindow)
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.delegate = self
        panel.contentView = bubbleView(size: size.width)
        return panel
    }

    func showMainWindow() {
        guard mainWindow != nil else { return }
        if panel?.isVisible == true {
            restoreMainWindow()
            return
        }
        restoreMainWindow()
    }

    private func restoreMainWindow() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        panel?.orderOut(nil)
        guard let mainWindow else { return }
        if let placement = LiveWindowLocator.frontmostVisibleWindow() {
            trackedScreen = placement.screen
            lastLiveWindowFrame = placement.frame
        }
        if let screen = trackedScreen {
            let visibleFrame = screen.visibleFrame
            let frame = mainWindow.frame
            mainWindow.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - frame.width / 2,
                y: visibleFrame.midY - frame.height / 2
            ))
        }
        mainWindow.level = Self.isAbleton(NSWorkspace.shared.frontmostApplication) ? .screenSaver : .normal
        mainWindow.isFloatingPanel = true
        if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
        mainWindow.orderFrontRegardless()
        mainWindow.makeKeyAndOrderFront(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isMovingProgrammatically,
              let movedPanel = notification.object as? NSPanel,
              movedPanel === panel,
              let liveFrame = lastLiveWindowFrame else { return }
        let defaults = UserDefaults.standard
        defaults.set(movedPanel.frame.minX - liveFrame.minX, forKey: positionXPreferenceKey)
        defaults.set(movedPanel.frame.minY - liveFrame.minY, forKey: positionYPreferenceKey)
        defaults.set(true, forKey: positionSavedPreferenceKey)
    }

    private var configuredScale: CGFloat {
        let value = UserDefaults.standard.double(forKey: sizePreferenceKey)
        return value > 0 ? CGFloat(value) : 1
    }

    private var configuredTransparency: Double {
        UserDefaults.standard.double(forKey: transparencyPreferenceKey)
    }

    private var isPositionLocked: Bool {
        UserDefaults.standard.bool(forKey: positionLockedPreferenceKey)
    }

    private func bubbleView(size: CGFloat) -> NSView {
        let view = PlugSpotBubbleControlView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.toolTip = "Open BubblePlug"
        view.isPositionLocked = isPositionLocked
        view.onActivate = { [weak self] in self?.restoreMainWindow() }
        view.onDrag = { [weak self] origin in self?.moveBubble(to: origin) }
        view.onDragStateChanged = { [weak self] isDragging in self?.isDraggingBubble = isDragging }
        return view
    }

    private func moveBubble(to origin: NSPoint) {
        guard !isPositionLocked, let panel, let screen = trackedScreen else { return }
        let frame = clampedFrame(origin: origin, size: panel.frame.size, on: screen)
        panel.setFrameOrigin(frame.origin)
        if let liveFrame = lastLiveWindowFrame {
            let defaults = UserDefaults.standard
            defaults.set(frame.minX - liveFrame.minX, forKey: positionXPreferenceKey)
            defaults.set(frame.minY - liveFrame.minY, forKey: positionYPreferenceKey)
            defaults.set(true, forKey: positionSavedPreferenceKey)
        }
    }

    func resetPosition() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: positionSavedPreferenceKey)
        defaults.removeObject(forKey: positionXPreferenceKey)
        defaults.removeObject(forKey: positionYPreferenceKey)
        if let panel, let placement = LiveWindowLocator.frontmostVisibleWindow() {
            trackedScreen = placement.screen
            lastLiveWindowFrame = placement.frame
            movePanel(to: bubbleFrame(size: panel.frame.size, on: placement.screen, near: placement.frame))
        }
    }

    private func startTracking() {
        trackingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.followLiveWindow()
        }
        trackingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func followLiveWindow() {
        if isDraggingBubble { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if Self.isAbleton(frontmost), let panel {
            panel.level = .screenSaver
            panel.isFloatingPanel = true
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            hideBubbleForOtherApplication()
            return
        }
        guard let placement = LiveWindowLocator.frontmostVisibleWindow() else {
            panel?.orderOut(nil)
            mainWindow?.orderOut(nil)
            panel?.level = .normal
            mainWindow?.level = .normal
            trackingTimer?.invalidate()
            trackingTimer = nil
            return
        }
        trackedScreen = placement.screen
        lastLiveWindowFrame = placement.frame
        guard let panel else { return }
        let frame = bubbleFrame(size: panel.frame.size, on: placement.screen, near: placement.frame)
        if hypot(panel.frame.origin.x - frame.origin.x, panel.frame.origin.y - frame.origin.y) > 2 {
            movePanel(to: frame)
        }
    }

    private func movePanel(to frame: NSRect) {
        guard let panel else { return }
        isMovingProgrammatically = true
        panel.setFrame(frame, display: true)
        isMovingProgrammatically = false
    }

    private func bubbleFrame(size: NSSize, on screen: NSScreen, near liveWindow: NSRect) -> NSRect {
        let margin: CGFloat = 16
        let defaults = UserDefaults.standard
        let preferredOrigin: NSPoint
        if defaults.bool(forKey: positionSavedPreferenceKey) {
            preferredOrigin = NSPoint(
                x: liveWindow.minX + defaults.double(forKey: positionXPreferenceKey),
                y: liveWindow.minY + defaults.double(forKey: positionYPreferenceKey)
            )
        } else {
            preferredOrigin = NSPoint(x: liveWindow.minX + margin, y: liveWindow.minY + margin)
        }
        return clampedFrame(origin: preferredOrigin, size: size, on: screen)
    }

    private func clampedFrame(origin preferredOrigin: NSPoint, size: NSSize, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let margin: CGFloat = 8
        let origin = NSPoint(
            x: min(max(preferredOrigin.x, visible.minX + margin), max(visible.minX + margin, visible.maxX - size.width - margin)),
            y: min(max(preferredOrigin.y, visible.minY + margin), max(visible.minY + margin, visible.maxY - size.height - margin))
        )
        return NSRect(origin: origin, size: size)
    }
}

private final class PlugSpotBubbleControlView: NSView {
    var isPositionLocked = false
    var onActivate: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?
    private var mouseDownLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?
    private var didDrag = false

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        BubblePlugArtwork.logo?.draw(in: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isPositionLocked,
              let mouseDownLocation,
              let windowOriginAtMouseDown else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - mouseDownLocation.x
        let dy = current.y - mouseDownLocation.y
        guard didDrag || hypot(dx, dy) >= 4 else { return }
        if !didDrag {
            didDrag = true
            onDragStateChanged?(true)
        }
        onDrag?(NSPoint(x: windowOriginAtMouseDown.x + dx, y: windowOriginAtMouseDown.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        let shouldActivate = !didDrag
        mouseDownLocation = nil
        windowOriginAtMouseDown = nil
        didDrag = false
        onDragStateChanged?(false)
        if shouldActivate { onActivate?() }
    }
}

private struct LiveWindowPlacement {
    let frame: NSRect
    let screen: NSScreen
}

private enum LiveWindowLocator {
    static func frontmostVisibleWindow() -> LiveWindowPlacement? {
        let liveApplications = NSWorkspace.shared.runningApplications.filter { application in
            application.bundleIdentifier?.localizedCaseInsensitiveContains("com.ableton.live") == true
        }
        let liveProcessIDs = Set(liveApplications.map(\.processIdentifier))
        guard !liveProcessIDs.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var largestLiveWindow: LiveWindowPlacement?
        var largestArea: CGFloat = 0
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  liveProcessIDs.contains(owner.int32Value),
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary else { continue }
            var quartzFrame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds as CFDictionary, &quartzFrame),
                  quartzFrame.width >= 320, quartzFrame.height >= 240,
                  let screen = NSScreen.screens.first(where: { candidate in
                      guard let number = candidate.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                      return CGDisplayBounds(CGDirectDisplayID(number.uint32Value)).contains(CGPoint(x: quartzFrame.midX, y: quartzFrame.midY))
                  }),
                  let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }

            let quartzScreen = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            let appKitFrame = NSRect(
                x: screen.frame.minX + quartzFrame.minX - quartzScreen.minX,
                y: screen.frame.maxY - (quartzFrame.minY - quartzScreen.minY) - quartzFrame.height,
                width: quartzFrame.width,
                height: quartzFrame.height
            )
            let area = quartzFrame.width * quartzFrame.height
            if area > largestArea {
                largestLiveWindow = LiveWindowPlacement(frame: appKitFrame, screen: screen)
                largestArea = area
            }
        }
        return largestLiveWindow
    }
}

private struct AbletonExportPreflight: Decodable {
    let ok: Bool
    let error: String?
    let matchedFamilies: Int
    let expectedFamilies: Int
    let mappedDevices: Int
    let coloredItemsToClear: Int
    let totalBrowserItems: Int
    let missing: [AbletonExportMissingFamily]
}

private struct AbletonExportMissingFamily: Decodable {
    let name: String
    let vendor: String
    let reason: String
}

private struct AbletonExportResult: Decodable {
    let ok: Bool
    let error: String?
    let backupDirectory: String?
    let matchedFamilies: Int?
}

private enum AbletonExportUIError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

private enum PluginListScope: String, CaseIterable, Identifiable {
    case all
    case favorites
    case recent
    case vendors
    case chainSets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .vendors: return "Manufacturers"
        case .chainSets: return "Chain Sets"
        }
    }
}

private enum PluginDisplayMode: String {
    case cards
    case list
}

private struct VendorFilterOption: Identifiable {
    let id: String
    let name: String
    let count: Int
}

private struct CategoryDraft: Identifiable {
    let id: String
    var name: String
    var colorIndex: Int
}

private struct CategoryManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [CategoryDraft]
    @State private var validationMessage: String?
    @State private var activeColorPickerID: String?
    let onSave: ([LocalCategory]) -> Void

    init(categories: [LocalCategory], onSave: @escaping ([LocalCategory]) -> Void) {
        _drafts = State(initialValue: categories.map { CategoryDraft(id: $0.id, name: $0.name, colorIndex: $0.colorIndex) })
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.title2.weight(.semibold))
            Text("Favorites use color 1. Create up to six categories using Ableton Collection colors.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach($drafts) { $category in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(collectionColor(category.colorIndex))
                            .frame(width: 12, height: 12)
                        TextField("Category name", text: $category.name)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            activeColorPickerID = activeColorPickerID == category.id ? nil : category.id
                        } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(collectionColor(category.colorIndex))
                                .frame(width: 26, height: 26)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: Binding(
                            get: { activeColorPickerID == category.id },
                            set: { if !$0 { activeColorPickerID = nil } }
                        ), arrowEdge: .bottom) {
                            HStack(spacing: 9) {
                                ForEach(availableColors(for: category.id), id: \.self) { index in
                                    Button {
                                        category.colorIndex = index
                                        activeColorPickerID = nil
                                    } label: {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(collectionColor(index))
                                            .frame(width: 30, height: 30)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                                                if category.colorIndex == index {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 13, weight: .bold))
                                                        .foregroundStyle(.white)
                                                        .shadow(color: .black.opacity(0.7), radius: 2)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .help("Select collection color")
                                    .accessibilityLabel("Select collection color")
                                }
                            }
                            .padding(12)
                            .modifier(BubblePlugSurface())
                        }
                        .help("Choose category color")
                        Button(role: .destructive) {
                            drafts.removeAll { $0.id == category.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete category")
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Add Category", action: addCategory)
                    .disabled(drafts.count >= 6 || freeColors.isEmpty)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 380)
        .modifier(BubblePlugSurface())
    }

    private var freeColors: [Int] {
        let used = Set(drafts.map(\.colorIndex))
        return (2...7).filter { !used.contains($0) }
    }

    private func availableColors(for id: String) -> [Int] {
        let current = drafts.first(where: { $0.id == id })?.colorIndex
        let usedByOthers = Set(drafts.filter { $0.id != id }.map(\.colorIndex))
        return (2...7).filter { $0 == current || !usedByOthers.contains($0) }
    }

    private func addCategory() {
        guard let color = freeColors.first else { return }
        let name = "Category \(drafts.count + 1)"
        drafts.append(CategoryDraft(id: UUID().uuidString, name: name, colorIndex: color))
        validationMessage = nil
    }

    private func save() {
        let names = drafts.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard names.allSatisfy({ !$0.isEmpty }) else {
            validationMessage = "Every category needs a name."
            return
        }
        let foldedNames = names.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        guard Set(foldedNames).count == foldedNames.count else {
            validationMessage = "Category names must be unique."
            return
        }
        let colorIndexes = drafts.map(\.colorIndex)
        guard Set(colorIndexes).count == colorIndexes.count else {
            validationMessage = "Each category needs a different color."
            return
        }
        onSave(zip(drafts, names).map { draft, name in LocalCategory(id: draft.id, name: name, colorIndex: draft.colorIndex) })
        dismiss()
    }

    private func collectionColor(_ index: Int) -> Color {
        switch index {
        case 1: return Color(red: 0.93, green: 0.30, blue: 0.34)
        case 2: return Color(red: 0.96, green: 0.49, blue: 0.24)
        case 3: return Color(red: 0.95, green: 0.73, blue: 0.22)
        case 4: return Color(red: 0.43, green: 0.72, blue: 0.31)
        case 5: return Color(red: 0.20, green: 0.72, blue: 0.65)
        case 6: return Color(red: 0.27, green: 0.52, blue: 0.88)
        default: return Color(red: 0.62, green: 0.38, blue: 0.82)
        }
    }
}

private struct PluginFamily: Identifiable {
    let id: String
    let name: String
    let vendor: String
    let variants: [PluginItem]

    var preferredVariant: PluginItem {
        variants.max { Self.preferenceRank($0) < Self.preferenceRank($1) } ?? variants[0]
    }

    var subtitle: String {
        if variants.count == 1 { return vendor }
        return "\(vendor) · \(variants.count) channel variants"
    }

    static func group(_ plugins: [PluginItem]) -> [PluginFamily] {
        var groups: [String: (name: String, vendor: String, items: [PluginItem])] = [:]
        for plugin in plugins {
            let vendor = plugin.vendor ?? ""
            let (name, channel) = familyNameAndChannel(for: plugin.name)
            let normalized = "\(vendor.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))|\(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))"
            let key = channel == nil ? "\(normalized)|\(plugin.id)" : normalized
            if groups[key] == nil {
                groups[key] = (name: name, vendor: vendor, items: [])
            }
            groups[key]?.items.append(plugin)
        }

        return groups.map { key, value in
            PluginFamily(
                id: key,
                name: value.name,
                vendor: value.vendor,
                variants: value.items.sorted {
                    let leftRank = preferenceRank($0)
                    let rightRank = preferenceRank($1)
                    return leftRank == rightRank ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : leftRank > rightRank
                }
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func channelFormat(for name: String) -> String {
        let (_, channel) = familyNameAndChannel(for: name)
        return channel ?? "Default"
    }

    fileprivate static func familyBaseName(for name: String) -> String {
        familyNameAndChannel(for: name).0
    }

    private static func familyNameAndChannel(for name: String) -> (String, String?) {
        guard let separator = name.lastIndex(of: " ") else { return (name, nil) }
        let suffix = String(name[name.index(after: separator)...])
        let parts = suffix.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ isChannelToken($0, composite: parts.count > 1) }) else { return (name, nil) }
        let base = String(name[..<separator]).trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return (name, nil) }
        return (base, suffix)
    }

    private static func isChannelToken(_ token: String, composite: Bool) -> Bool {
        let labels: Set<String> = ["mono", "stereo", "quad", "lcr", "ambix", "ambix-fuma", "fuma-ambix"]
        if labels.contains(token.lowercased()) { return true }
        let numericPattern = composite ? #"^\d+(?:\.\d+){0,2}$"# : #"^\d+\.\d+(?:\.\d+)?$"#
        return token.range(of: numericPattern, options: .regularExpression) != nil
    }

    private static func preferenceRank(_ plugin: PluginItem) -> Int {
        switch channelFormat(for: plugin.name).lowercased() {
        case "mono/stereo": return 5
        case "stereo": return 4
        case "default": return 3
        case "mono": return 2
        default: return 1
        }
    }
}
