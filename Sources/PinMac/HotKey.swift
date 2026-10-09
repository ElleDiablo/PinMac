import Carbon.HIToolbox

/// A system-wide keyboard shortcut. Carbon's RegisterEventHotKey is still the
/// simplest way to do this on macOS and, unlike event taps, needs no permission.
final class HotKey {
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    /// Returns nil if the shortcut can't be registered (e.g. another app owns it).
    init?(_ shortcut: Shortcut, action: @escaping @MainActor () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()

            // Every handler sees every hot key; only act on our own.
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }

            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &eventType, userData, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x504E_4D43), id: id) // "PNMC"
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
