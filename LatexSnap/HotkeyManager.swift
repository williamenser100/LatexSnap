import Carbon.HIToolbox

class HotkeyManager {
    private let callback: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    func register() {
        let hotKeyID = EventHotKeyID(signature: fourCC("LSNP"), id: 1)
        let modifiers = UInt32(cmdKey | shiftKey | controlKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_L), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let ptr = userData else { return noErr }
                Unmanaged<HotkeyManager>.fromOpaque(ptr).takeUnretainedValue().callback()
                return noErr
            },
            1, &eventType, selfPtr, &eventHandlerRef
        )
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
    }

    private func fourCC(_ s: String) -> FourCharCode {
        s.unicodeScalars.prefix(4).reduce(0) { ($0 << 8) | FourCharCode($1.value) }
    }
}
