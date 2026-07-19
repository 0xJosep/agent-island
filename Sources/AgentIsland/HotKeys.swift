import AppKit
import Carbon.HIToolbox

final class HotKeys {
    private static var shared: HotKeys?

    private let store: SessionStore
    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?

    init(store: SessionStore) {
        self.store = store
    }

    func register() {
        Self.shared = self
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            HotKeys.shared?.handle(id: hotKeyID.id)
            return noErr
        }, 1, &spec, nil, &handler)

        registerKey(id: 1, keyCode: UInt32(kVK_ANSI_A))
        registerKey(id: 2, keyCode: UInt32(kVK_ANSI_D))
        registerKey(id: 3, keyCode: UInt32(kVK_ANSI_I))
    }

    private func registerKey(id: UInt32, keyCode: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x41_49_53_4C), id: id)
        RegisterEventHotKey(
            keyCode,
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        refs.append(ref)
    }

    private func handle(id: UInt32) {
        DispatchQueue.main.async { [store] in
            switch id {
            case 1: store.approveTopPermission()
            case 2: store.denyTopPermission()
            case 3: store.toggleIsland()
            default: break
            }
        }
    }
}
