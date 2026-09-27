import AppKit
import Carbon.HIToolbox
import SwiftUI

final class PlugSpotGlobalHotKeyController {
    static let signature = OSType(0x50534754) // PSGT
    static let hotKeyID = UInt32(1)

    var onPress: (() -> Void)?
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    init() {
        installHandler()
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        unregister()
        let identifier = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        return RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var receivedID = EventHotKeyID(signature: 0, id: 0)
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )
                guard status == noErr,
                      receivedID.signature == PlugSpotGlobalHotKeyController.signature,
                      receivedID.id == PlugSpotGlobalHotKeyController.hotKeyID else { return noErr }
                let controller = Unmanaged<PlugSpotGlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { controller.onPress?() }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )
    }
}

struct PlugSpotSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var bubbleScale: Double
    @Binding var bubbleTransparency: Double
    @Binding var bubblePositionLocked: Bool
    @Binding var shortcutKeyCode: Int
    @Binding var shortcutModifiers: Int
    @Binding var shortcutLabel: String
    @Binding var shortcutStatus: String
    @Binding var imageStartupMode: String
    let imageScanIsRunning: Bool
    let missingImageCount: Int
    let onLoadAllImages: () -> Void
    let onRecordingChanged: (Bool) -> Void
    let onShortcutChanged: () -> Void
    let onBubbleChanged: () -> Void
    let onResetBubblePosition: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                PlugSpotAudioMark(size: 44)
                Text("Settings").font(.title2.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Bubble")
                    .font(.headline)
                Picker("Size", selection: $bubbleScale) {
                    Text("75%").tag(0.75)
                    Text("100%").tag(1.0)
                    Text("120%").tag(1.2)
                    Text("150%").tag(1.5)
                }
                .pickerStyle(.segmented)
                .onChange(of: bubbleScale) { _ in onBubbleChanged() }

                HStack {
                    Text("Transparency")
                    Slider(value: $bubbleTransparency, in: 0...100, step: 1)
                        .onChange(of: bubbleTransparency) { _ in onBubbleChanged() }
                    Text("\(Int(bubbleTransparency))%")
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                Text("0% is solid; 100% is fully transparent. Use the shortcut to reopen an invisible bubble.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Lock Position", isOn: $bubblePositionLocked)
                    .onChange(of: bubblePositionLocked) { _ in onBubbleChanged() }
                Button("Reset Bubble Position") { onResetBubblePosition() }
                    .buttonStyle(.bordered)
                    .help("Move the bubble back to the lower left corner of the Ableton window")
            }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Text("Plugin Images")
                    .font(.headline)
                Picker("At startup", selection: $imageStartupMode) {
                    Text("Ask me").tag("ask")
                    Text("Load missing images").tag("scan")
                    Text("Open without loading").tag("defer")
                }
                Text("Plugins that need activation or have never been opened may show setup, activation, or error screens instead of their editor. Replace those images in Manage Images.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("\(missingImageCount) plugin images missing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Load All Plugin Images…", action: onLoadAllImages)
                        .disabled(imageScanIsRunning || missingImageCount == 0)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Text("Keyboard Shortcut")
                    .font(.headline)
                HStack {
                    Text("Open BubblePlug")
                    Spacer()
                    ShortcutRecorderButton(
                        label: shortcutLabel,
                        onRecordingChanged: onRecordingChanged
                    ) { keyCode, modifiers, label in
                        shortcutKeyCode = Int(keyCode)
                        shortcutModifiers = Int(modifiers)
                        shortcutLabel = label
                        shortcutStatus = ""
                        onShortcutChanged()
                    }
                }
                if !shortcutStatus.isEmpty {
                    Text(shortcutStatus)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
        .modifier(BubblePlugSurface())
    }
}

private struct ShortcutRecorderButton: View {
    let label: String
    let onRecordingChanged: (Bool) -> Void
    let onCapture: (UInt32, UInt32, String) -> Void
    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        Button(isRecording ? "Press shortcut…" : label) {
            isRecording.toggle()
        }
        .buttonStyle(.bordered)
        .onChange(of: isRecording) { recording in
            if recording { beginRecording() } else { endRecording() }
        }
        .onDisappear(perform: endRecording)
    }

    private func beginRecording() {
        onRecordingChanged(true)
        let recordingBinding = $isRecording
        let capture = onCapture
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                DispatchQueue.main.async { recordingBinding.wrappedValue = false }
                return nil
            }
            let modifiers = Self.carbonModifiers(event.modifierFlags)
            guard modifiers & UInt32(cmdKey | controlKey) != 0 else { return nil }
            let keyName = event.charactersIgnoringModifiers?.uppercased() ?? ""
            let label = Self.shortcutLabel(modifiers: modifiers, keyName: keyName, keyCode: UInt32(event.keyCode))
            DispatchQueue.main.async {
                capture(UInt32(event.keyCode), modifiers, label)
                recordingBinding.wrappedValue = false
            }
            return nil
        }
    }

    private func endRecording() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        onRecordingChanged(false)
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    private static func shortcutLabel(modifiers: UInt32, keyName: String, keyCode: UInt32) -> String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        value += keyName.isEmpty ? "Key \(keyCode)" : keyName
        return value
    }
}
