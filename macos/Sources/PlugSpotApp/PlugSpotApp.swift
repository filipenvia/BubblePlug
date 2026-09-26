import PlugSpotCore
import AppKit
import CoreGraphics
import SwiftUI

@main
struct PlugSpotApp: App {
    var body: some Scene {
        WindowGroup {
            PlugSpotView()
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

private struct PlugSpotView: View {
    @State private var bubbleController = PlugSpotBubbleController()
    @StateObject private var artworkStore = PluginArtworkStore()
    @State private var didInitializeWindow = false
    @State private var windowButtonTarget: PlugSpotWindowButtonTarget?
    @State private var scope: PluginListScope = .all
    @State private var isMixerVisible = false
    @AppStorage("plugspot.displayMode") private var displayModeRaw = PluginDisplayMode.list.rawValue
    @AppStorage("plugspot.cachedLiveVersion") private var cachedLiveVersion = ""
    @AppStorage("plugspot.cachedCatalogJSON") private var cachedCatalogJSON = Data()
    @AppStorage("plugspot.bubble.scale") private var bubbleScale = 1.0
    @AppStorage("plugspot.bubble.transparency") private var bubbleTransparency = 0.0
    @AppStorage("plugspot.bubble.position.locked") private var bubblePositionLocked = false
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
    @State private var shortcutStatus = ""
    @State private var globalHotKeyController: PlugSpotGlobalHotKeyController?
    @State private var showAbletonExportConfirmation = false
    @State private var showAbletonExportError = false
    @State private var abletonExportError = ""
    @State private var abletonExportDocument: PlugSpotLibraryDocument?
    @State private var abletonExportPreflight: AbletonExportPreflight?
    private let library = AbletonLibrary()
    private let localStore: LocalLibraryStore? = try? LocalLibraryStore()

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
                PlugSpotAudioMark()
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
                .disabled(isLoadingLibrary)
                Menu {
                    Section {
                        Button("Settings…") { isSettingsPresented = true }
                    }
                    Section {
                        Button("Import Ableton Collections…", action: importAbletonOrganization)
                            .disabled(isImportingOrganization)
                        Button("Import BubblePlug Library…", action: importPlugSpotLibrary)
                        Button("Export JSON Backup…", action: exportPlugSpotLibrary)
                        Button("Export Collections to Ableton…", action: prepareAbletonExport)
                            .disabled(isPreparingAbletonExport)
                    }
                    Section {
                        Button("Manage Categories…") { isCategoryManagerPresented = true }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Import and export library")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            if isMixerVisible {
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
            }

            Group {
            if scope == .vendors, let selectedVendorFilter {
                HStack(spacing: 8) {
                    Button { self.selectedVendorFilter = nil } label: {
                        Label("All Vendors", systemImage: "chevron.left")
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
                TextField("Search plugins or vendors", text: $searchText)
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
                    emptyState(title: "No Vendors Found", symbol: "building.2", detail: "Try a different search.")
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
        }
        .sheet(isPresented: $isCategoryManagerPresented) {
            CategoryManagerView(categories: categories) { updated in
                saveCategories(updated)
            }
        }
        .sheet(isPresented: $isSettingsPresented) { settingsSheet }
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
            onRecordingChanged: { isRecording in
                if isRecording { globalHotKeyController?.unregister() }
                else { registerGlobalHotKey() }
            },
            onShortcutChanged: registerGlobalHotKey,
            onBubbleChanged: {
                bubbleController.updateAppearance(scale: bubbleScale, transparency: bubbleTransparency, positionLocked: bubblePositionLocked)
            }
        )
    }

    @ViewBuilder
    private var pluginResultsView: some View {
        if displayMode == .list {
                List(filteredFamilies, selection: familySelection) { family in
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
                    .task(id: "\(family.id)|\(liveVersion ?? "")") {
                        guard let liveVersion else { return }
                        artworkStore.requestPluginImage(for: family.preferredVariant, familyID: family.id, liveVersion: liveVersion)
                    }
                    .tag(family.id)
                    .padding(.vertical, 2)
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        loadPlugin(family.preferredVariant, family: family)
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
                        selectAndQueue(family)
                    case .second:
                        loadPlugin(family.preferredVariant, family: family)
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
        .task(id: "\(family.id)|\(liveVersion ?? "")") {
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
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.gradient)
                    Text(monogram(for: family.name))
                        .font(.system(size: min(height * 0.46, 28), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
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
                Spacer()
                Button("Clear") { chainQueue.removeAll() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(isLoadingChain)
                Button(isLoadingChain ? "Loading…" : "Load Chain") { loadChain() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLoadingChain || chainQueue.isEmpty)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(chainQueue.enumerated()), id: \.element.id) { index, entry in
                        let family = pluginFamilies.first(where: { $0.id == entry.familyID })
                        VStack(alignment: .leading, spacing: 4) {
                            Text(family?.name ?? "Unavailable plugin")
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: 112, alignment: .leading)
                            HStack(spacing: 5) {
                                Button { moveQueueItem(at: index, by: -1) } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .disabled(index == 0 || isLoadingChain)
                                Button { moveQueueItem(at: index, by: 1) } label: {
                                    Image(systemName: "chevron.right")
                                }
                                .disabled(index == chainQueue.count - 1 || isLoadingChain)
                                Button { chainQueue.remove(at: index) } label: {
                                    Image(systemName: "xmark")
                                }
                                .disabled(isLoadingChain)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(7)
                        .background(PlugSpotPalette.chainTile, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(PlugSpotPalette.edge, lineWidth: 1))
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PlugSpotPalette.chainShelf)
        .overlay(alignment: .top) { Rectangle().fill(PlugSpotPalette.iridescence).frame(height: 1).opacity(0.55) }
    }

    private var isLoadingChain: Bool {
        loadingPluginID == "__plugspot_chain__"
    }

    private func selectAndQueue(_ family: PluginFamily) {
        guard !isLoadingChain else { return }
        let variant = family.preferredVariant
        selectedFamilyID = family.id
        selectedVariantID = variant.id
        chainQueue.append(QueuedPlugin(familyID: family.id, pluginID: variant.id))
        status = "Added \(family.name) to the chain."
        isError = false
    }

    private func moveQueueItem(at index: Int, by offset: Int) {
        let destination = index + offset
        guard chainQueue.indices.contains(index), chainQueue.indices.contains(destination), !isLoadingChain else { return }
        let item = chainQueue.remove(at: index)
        chainQueue.insert(item, at: destination)
    }

    private func loadChain() {
        guard !chainQueue.isEmpty, loadingPluginID == nil else { return }
        let queued = chainQueue
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
                    bubbleController.show(minimizing: NSApp.keyWindow ?? NSApp.mainWindow)
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
                    } else if !hasObservedConnection && plugins.isEmpty && !isLoadingLibrary {
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
                .task(id: "\(option.id)|\(liveVersion ?? "")") {
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
                        .task(id: "\(option.id)|\(liveVersion ?? "")") {
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
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.16))
                    Text(monogram(for: vendor))
                        .font(.system(size: min(height * 0.58, 26), weight: .bold, design: .rounded))
                        .foregroundStyle(.tint)
                }
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
            return "\(filteredVendorOptions.count) vendors"
        }
        var qualifiers: [String] = []
        if !selectedCategoryFilters.isEmpty { qualifiers.append("\(selectedCategoryFilters.count) active categories") }
        let suffix = qualifiers.isEmpty ? "" : " · " + qualifiers.joined(separator: " · ")
        return "\(filteredFamilies.count) \(scopeLabel)\(suffix)"
    }

    private var familySelection: Binding<String?> {
        Binding(
            get: { selectedFamilyID },
            set: {
                guard let id = $0, let family = pluginFamilies.first(where: { $0.id == id }) else {
                    selectedFamilyID = $0
                    selectedVariantID = nil
                    return
                }
                selectAndQueue(family)
                selectedVariantID = nil
            }
        )
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
                cachedLiveVersion = detectedLiveVersion
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
        window.title = "BubblePlug"
        window.backgroundColor = NSColor(PlugSpotPalette.canvas)
        bubbleController.prepareStartupWindow(window)
        window.styleMask.remove(.closable)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        guard let minimizeButton = window.standardWindowButton(.miniaturizeButton) else { return }

        let target: PlugSpotWindowButtonTarget
        if let current = windowButtonTarget, current.window === window {
            target = current
        } else {
            target = PlugSpotWindowButtonTarget(window: window) { [weak bubbleController] window in
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
        loadingPluginID = plugin.id
        isError = false
        status = "Loading \(family.name) (\(channelLabel(for: plugin)))…"

        Task {
            do {
                let result = try await library.loadPlugin(id: plugin.id)
                do {
                    try localStore?.recordLoadRequest(id: family.id, name: family.name, vendor: family.vendor, format: plugin.format)
                    loadLocalState()
                } catch {
                    localStoreError = error.localizedDescription
                }
                status = "Load request for \(family.name) sent to “\(result.trackName)”. Check Live."
                chainQueue.removeAll { $0.pluginID == plugin.id }
                await MainActor.run {
                    bubbleController.show(minimizing: NSApp.keyWindow ?? NSApp.mainWindow)
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
                for label in imported.labels where (2...7).contains(label.colorIndex) {
                    if let existing = existingCategories.first(where: { $0.name.caseInsensitiveCompare(label.name) == .orderedSame }) {
                        categoryByAbletonIndex[label.colorIndex] = existing
                        continue
                    }
                    guard existingCategories.count < 6 else { continue }
                    let usedIndexes = Set(existingCategories.map(\.colorIndex))
                    let index = usedIndexes.contains(label.colorIndex)
                        ? (2...7).first(where: { !usedIndexes.contains($0) })
                        : label.colorIndex
                    guard let index else { continue }
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
    let pluginID: String
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
            onWindow(window)
        }
    }
}

private final class PlugSpotWindowObservingView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindow?(window)
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

private final class PlugSpotBubbleController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private weak var mainWindow: NSWindow?
    private weak var trackedScreen: NSScreen?
    private var trackingTimer: Timer?
    private var appActivationObserver: NSObjectProtocol?
    private var mainWindowFocusObserver: NSObjectProtocol?
    private var lastLiveWindowFrame: NSRect?
    private var isMovingProgrammatically = false
    private let sizePreferenceKey = "plugspot.bubble.scale"
    private let transparencyPreferenceKey = "plugspot.bubble.transparency"
    private let positionLockedPreferenceKey = "plugspot.bubble.position.locked"
    private let positionSavedPreferenceKey = "plugspot.bubble.position.saved"
    private let positionXPreferenceKey = "plugspot.bubble.position.x"
    private let positionYPreferenceKey = "plugspot.bubble.position.y"

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
    }

    private static func isAbleton(_ application: NSRunningApplication?) -> Bool {
        application?.bundleIdentifier?.localizedCaseInsensitiveContains("com.ableton.live") == true
    }

    private func handleLiveActivation() {
        guard let mainWindow else { return }
        show(minimizing: mainWindow)
    }

    func prepareStartupWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        observeMainWindowFocus(window)
        window.orderOut(nil)
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
            if NSApp.isActive, let keyWindow = NSApp.keyWindow, keyWindow !== window {
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
        panel.isMovableByWindowBackground = !positionLocked
        panel.contentView = NSHostingView(rootView: bubbleView(size: size))
        var frame = panel.frame
        frame.size = NSSize(width: size, height: size)
        movePanel(to: frame)
        followLiveWindow()
    }

    func show(minimizing window: NSWindow?) {
        guard let window else { return }
        mainWindow = window
        let scale = configuredScale
        let size = NSSize(width: 58 * scale, height: 58 * scale)
        let bubble = panel ?? makePanel(size: size)
        panel = bubble
        bubble.alphaValue = CGFloat(max(0, min(100, 100 - configuredTransparency)) / 100)
        bubble.level = .normal
        bubble.isFloatingPanel = false
        bubble.isMovableByWindowBackground = !isPositionLocked
        bubble.collectionBehavior = [.fullScreenAuxiliary]
        let fallbackScreen = window.screen ?? NSScreen.main
        if let fallbackScreen {
            trackedScreen = fallbackScreen
            movePanel(to: bubbleFrame(size: size, on: fallbackScreen, near: window.frame))
        }
        bubble.orderFront(nil)
        window.orderOut(nil)
        followLiveWindow()
        startTracking()
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
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = !isPositionLocked
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: bubbleView(size: size.width))
        return panel
    }

    func showMainWindow() {
        guard let mainWindow else { return }
        if panel?.isVisible == true {
            restoreMainWindow()
            return
        }
        mainWindow.collectionBehavior.insert(.moveToActiveSpace)
        NSApp.activate(ignoringOtherApps: true)
        if mainWindow.isMiniaturized { mainWindow.deminiaturize(nil) }
        mainWindow.orderFrontRegardless()
        mainWindow.makeKeyAndOrderFront(nil)
    }

    private func restoreMainWindow() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        panel?.orderOut(nil)
        guard let mainWindow else { return }
        mainWindow.collectionBehavior.insert(.moveToActiveSpace)
        if let screen = trackedScreen {
            let visibleFrame = screen.visibleFrame
            let frame = mainWindow.frame
            mainWindow.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - frame.width / 2,
                y: visibleFrame.midY - frame.height / 2
            ))
        }
        NSApp.activate(ignoringOtherApps: true)
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

    private func bubbleView(size: CGFloat) -> PlugSpotBubbleView {
        PlugSpotBubbleView(
            size: size,
            isPositionLocked: isPositionLocked,
            onActivate: { [weak self] in self?.restoreMainWindow() },
            onMove: { [weak self] delta in self?.moveBubble(by: delta) }
        )
    }

    private func moveBubble(by delta: CGSize) {
        guard !isPositionLocked, let panel, let screen = trackedScreen else { return }
        let newOrigin = NSPoint(x: panel.frame.minX + delta.width, y: panel.frame.minY - delta.height)
        let frame = clampedFrame(origin: newOrigin, size: panel.frame.size, on: screen)
        panel.setFrameOrigin(frame.origin)
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
        guard let placement = LiveWindowLocator.frontmostVisibleWindow() else { return }
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
            preferredOrigin = NSPoint(x: liveWindow.minX + margin, y: liveWindow.maxY - size.height - margin)
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

private struct PlugSpotBubbleView: View {
    let size: CGFloat
    let isPositionLocked: Bool
    let onActivate: () -> Void
    let onMove: (CGSize) -> Void
    @State private var previousTranslation = CGSize.zero
    @State private var dragged = false

    var body: some View {
        Button {
            if !dragged { onActivate() }
            dragged = false
            previousTranslation = .zero
        } label: {
            PlugSpotAudioMark(size: size)
        }
        .buttonStyle(.plain)
        .help("Open BubblePlug")
        .frame(width: size, height: size)
        .simultaneousGesture(DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !isPositionLocked else { return }
                dragged = true
                let delta = CGSize(
                    width: value.translation.width - previousTranslation.width,
                    height: value.translation.height - previousTranslation.height
                )
                previousTranslation = value.translation
                onMove(delta)
            }
            .onEnded { _ in
                previousTranslation = .zero
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { dragged = false }
            })
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .vendors: return "Vendors"
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
                        Picker(selection: $category.colorIndex) {
                            ForEach(availableColors(for: category.id), id: \.self) { index in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(collectionColor(index))
                                    .frame(width: 16, height: 16)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 3)
                                            .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                                    }
                                    .tag(index)
                                    .accessibilityLabel(Text("Color \(index)"))
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(collectionColor(category.colorIndex))
                                .frame(width: 16, height: 16)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                                }
                                .accessibilityLabel("Category color")
                        }
                        .labelsHidden()
                        .frame(width: 38)
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
        return "\(vendor) · \(variants.count) variantes de canal"
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
