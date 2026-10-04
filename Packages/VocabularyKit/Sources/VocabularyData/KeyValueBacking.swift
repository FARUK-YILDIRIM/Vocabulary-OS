import Foundation

/// The storage behind `SettingsStore`: iCloud's key-value store in the app, memory in tests.
@MainActor
public protocol KeyValueBacking: AnyObject {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
    /// Values that stay on this device and never sync.
    func deviceData(forKey key: String) -> Data?
    func setDeviceData(_ data: Data?, forKey key: String)
    /// Receives the keys another device changed. `SettingsStore` sets this.
    var onExternalChange: (([String]) -> Void)? { get set }
}

/// Keeps values in memory; for tests and SwiftUI previews.
@MainActor
public final class InMemoryKeyValueBacking: KeyValueBacking {
    private var values: [String: Data] = [:]
    private var deviceValues: [String: Data] = [:]
    public var onExternalChange: (([String]) -> Void)?

    public init() {}

    public func data(forKey key: String) -> Data? { values[key] }

    public func setData(_ data: Data?, forKey key: String) { values[key] = data }

    public func deviceData(forKey key: String) -> Data? { deviceValues[key] }

    public func setDeviceData(_ data: Data?, forKey key: String) { deviceValues[key] = data }

    /// Behaves like a change arriving from another device.
    public func simulateExternalChange(key: String, value: Data?) {
        values[key] = value
        onExternalChange?([key])
    }
}

/// The part of `NSUbiquitousKeyValueStore` we use, so tests can substitute it.
public protocol CloudKeyValueStoring: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStoring {}

/// iCloud key-value store with a `UserDefaults` mirror (ADR-002).
///
/// The mirror keeps settings working where the key-value store does not sync: no iCloud account, or
/// before the first sync. Builds without the key-value store entitlement pass `cloud: nil` and use
/// the mirror alone. Reads prefer iCloud, so the latest value from any device wins.
///
/// In the app, the mirror lives in the App Group, where the Share extension reads it with
/// `cloud: nil`. Reads therefore copy iCloud values into the mirror, so the extension never sees
/// older settings than the app.
@MainActor
public final class UbiquitousKeyValueBacking: KeyValueBacking {
    public var onExternalChange: (([String]) -> Void)?

    private let cloud: (any CloudKeyValueStoring)?
    private let mirror: UserDefaults
    private var observer: (any NSObjectProtocol)?

    public init(cloud: (any CloudKeyValueStoring)?, mirror: UserDefaults = .standard) {
        self.cloud = cloud
        self.mirror = mirror
        if let store = cloud as? NSUbiquitousKeyValueStore {
            observer = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: store,
                queue: .main
            ) { [weak self] notification in
                let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
                MainActor.assumeIsolated {
                    self?.handleExternalChange(changedKeys: keys)
                }
            }
            // Apple recommends synchronizing at launch so the first external change arrives promptly.
            store.synchronize()
        }
    }

    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func data(forKey key: String) -> Data? {
        let local = mirror.data(forKey: mirrorKey(key))
        guard let remote = cloud?.data(forKey: key) else { return local }
        if remote != local {
            mirror.set(remote, forKey: mirrorKey(key))
        }
        return remote
    }

    public func setData(_ data: Data?, forKey key: String) {
        if let data {
            cloud?.set(data, forKey: key)
            mirror.set(data, forKey: mirrorKey(key))
        } else {
            cloud?.removeObject(forKey: key)
            mirror.removeObject(forKey: mirrorKey(key))
        }
    }

    /// Only in the mirror, which the Share extension reads too.
    public func deviceData(forKey key: String) -> Data? {
        mirror.data(forKey: deviceKey(key))
    }

    public func setDeviceData(_ data: Data?, forKey key: String) {
        mirror.set(data, forKey: deviceKey(key))
    }

    func handleExternalChange(changedKeys: [String]) {
        for key in changedKeys {
            mirror.set(cloud?.data(forKey: key), forKey: mirrorKey(key))
        }
        onExternalChange?(changedKeys)
    }

    private func mirrorKey(_ key: String) -> String { "vos.\(key)" }

    private func deviceKey(_ key: String) -> String { "vos.device.\(key)" }
}
