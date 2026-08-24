import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A key plus modifiers, stored in the form Carbon's RegisterEventHotKey expects.
struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int // Carbon flags: cmdKey, optionKey, controlKey, shiftKey
    var key: String    // display name of the key, e.g. "T" or "Space"

    static let `default` = Shortcut(keyCode: kVK_ANSI_T, modifiers: controlKey | cmdKey, key: "T")

    /// Modifier symbols in Apple's standard order, e.g. "⌃⌘T".
    var displayString: String {
        var text = ""
        if modifiers & controlKey != 0 { text += "⌃" }
        if modifiers & optionKey != 0 { text += "⌥" }
        if modifiers & shiftKey != 0 { text += "⇧" }
        if modifiers & cmdKey != 0 { text += "⌘" }
        return text + key
    }

    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & controlKey != 0 { flags.insert(.control) }
        if modifiers & optionKey != 0 { flags.insert(.option) }
        if modifiers & shiftKey != 0 { flags.insert(.shift) }
        if modifiers & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    /// A menu key equivalent, when the key is a plain character.
    var menuKeyEquivalent: String {
        key.count == 1 ? key.lowercased() : ""
    }

    /// Builds a shortcut from a key press. Requires ⌃, ⌥ or ⌘, so ordinary
    /// typing can never trigger it.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.control, .option, .command]).isEmpty else { return nil }

        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }

        let keyCode = Int(event.keyCode)
        guard let key = Self.specialKeys[keyCode]
                ?? event.characters(byApplyingModifiers: [])?.uppercased().nilIfBlank
        else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, key: key)
    }

    init(keyCode: Int, modifiers: Int, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    // MARK: Storage

    static func load() -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: "shortcut"),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data)
        else { return .default }
        return shortcut
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "shortcut")
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

/// State behind the shortcut popover.
@MainActor
final class ShortcutModel: ObservableObject {
    @Published private(set) var shortcut = Shortcut.load()
    @Published private(set) var isRecording = false
    @Published private(set) var message: String?

    /// Tries to register a shortcut; returns false if it's unavailable.
    var register: ((Shortcut) -> Bool)?
    /// Pauses the current shortcut while recording, so pressing it doesn't pin.
    var pause: (() -> Void)?

    private var monitor: Any?

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        message = nil
        pause?()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil // swallow the key press
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        _ = register?(shortcut) // restore the current one
    }

    func reset() {
        stopRecording()
        apply(.default)
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == kVK_Escape {
            stopRecording()
            return
        }
        guard let candidate = Shortcut(event: event) else {
            message = "Include ⌃, ⌥ or ⌘ in the shortcut."
            return
        }
        stopRecording()
        apply(candidate)
    }

    private func apply(_ candidate: Shortcut) {
        if register?(candidate) == true {
            shortcut = candidate
            shortcut.save()
            message = nil
        } else {
            _ = register?(shortcut)
            message = "\(candidate.displayString) is already used by another app."
        }
    }
}

struct ShortcutView: View {
    @ObservedObject var model: ShortcutModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pin Shortcut").font(.headline)
            Text("Pins or unpins the frontmost window.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                model.isRecording ? model.stopRecording() : model.startRecording()
            } label: {
                Text(model.isRecording ? "Type a shortcut…" : model.shortcut.displayString)
                    .font(.system(size: model.isRecording ? 14 : 20, weight: .medium, design: .rounded))
                    .foregroundStyle(model.isRecording ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(model.isRecording ? Color.accentColor : Color.primary.opacity(0.15),
                                          lineWidth: model.isRecording ? 2 : 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click, then press the keys you want to use")

            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.red)
            } else {
                Text(model.isRecording ? "Press Esc to cancel." : "Click the box to record a new shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Reset to \(Shortcut.default.displayString)") { model.reset() }
                    .disabled(model.shortcut == .default && !model.isRecording)
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}
