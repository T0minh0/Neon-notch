import Carbon.HIToolbox
import Combine
import Foundation

enum GlobalHotKeyError: LocalizedError, Equatable {
    case missingModifier
    case reservedShortcut
    case registrationConflict

    var errorDescription: String? {
        switch self {
        case .missingModifier: "Use pelo menos Control, Option, Shift ou Command."
        case .reservedShortcut: "Esse atalho é reservado pelo macOS."
        case .registrationConflict: "Esse atalho já está em uso por outro app."
        }
    }
}

@MainActor
protocol HotKeyBackend: AnyObject {
    var onTrigger: (() -> Void)? { get set }
    func register(_ configuration: GlobalShortcutConfiguration) throws
    func unregister()
}

@MainActor
final class GlobalHotKeyService: ObservableObject {
    @Published private(set) var configuration: GlobalShortcutConfiguration
    @Published private(set) var registrationError: String?
    @Published private(set) var isRegistered = false

    var onTrigger: (() -> Void)?

    private let backend: any HotKeyBackend
    private let defaults: UserDefaults
    private let storageKey = "globalShortcutConfiguration.v1"

    init(
        backend: any HotKeyBackend = CarbonHotKeyBackend(),
        defaults: UserDefaults = .standard
    ) {
        self.backend = backend
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(GlobalShortcutConfiguration.self, from: data) {
            configuration = saved
        } else {
            configuration = .default
        }
        backend.onTrigger = { [weak self] in self?.onTrigger?() }
    }

    func start() {
        do {
            try Self.validate(configuration)
            try backend.register(configuration)
            isRegistered = true
            registrationError = nil
        } catch {
            isRegistered = false
            registrationError = error.localizedDescription
        }
    }

    @discardableResult
    func update(_ candidate: GlobalShortcutConfiguration) -> Bool {
        do {
            try Self.validate(candidate)
        } catch {
            registrationError = error.localizedDescription
            return false
        }
        if candidate.keyCode == configuration.keyCode,
           candidate.modifiers == configuration.modifiers {
            configuration = candidate
            persist()
            registrationError = nil
            return true
        }

        let previous = configuration
        backend.unregister()
        do {
            try backend.register(candidate)
            configuration = candidate
            isRegistered = true
            registrationError = nil
            persist()
            return true
        } catch {
            do {
                try backend.register(previous)
                isRegistered = true
            } catch {
                isRegistered = false
            }
            registrationError = GlobalHotKeyError.registrationConflict.localizedDescription
            return false
        }
    }

    func updateTarget(_ target: GlobalShortcutTarget) {
        configuration.target = target
        persist()
    }

    func restoreAfterWake() {
        backend.unregister()
        start()
    }

    static func validate(_ configuration: GlobalShortcutConfiguration) throws {
        guard !configuration.modifiers.isEmpty else { throw GlobalHotKeyError.missingModifier }
        let isSpace = configuration.keyCode == 49
        let reserved: Set<GlobalShortcutModifiers> = [
            [.command], [.control], [.command, .option]
        ]
        if isSpace, reserved.contains(configuration.modifiers) {
            throw GlobalHotKeyError.reservedShortcut
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

@MainActor
final class CarbonHotKeyBackend: HotKeyBackend {
    var onTrigger: (() -> Void)?

    private var hotKeyReference: EventHotKeyRef?
    private var handlerReference: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let backend = Unmanaged<CarbonHotKeyBackend>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { backend.onTrigger?() }
                return noErr
            },
            1,
            &eventType,
            context,
            &handlerReference
        )
    }

    func register(_ configuration: GlobalShortcutConfiguration) throws {
        unregister()
        let identifier = EventHotKeyID(signature: 0x4E4E4F54, id: 1) // NNOT
        let status = RegisterEventHotKey(
            configuration.keyCode,
            configuration.modifiers.carbonFlags,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard status == noErr else {
            hotKeyReference = nil
            throw GlobalHotKeyError.registrationConflict
        }
    }

    func unregister() {
        guard let hotKeyReference else { return }
        UnregisterEventHotKey(hotKeyReference)
        self.hotKeyReference = nil
    }
}

private extension GlobalShortcutModifiers {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }
}
