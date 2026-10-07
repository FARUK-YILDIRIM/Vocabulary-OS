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
    /// Keys the learner changed on this device since launch.
    private var keysWrittenHere: Set<String> = []

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
                let reason = ExternalChangeReason(code: notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int)
                MainActor.assumeIsolated {
                    self?.handleExternalChange(changedKeys: keys, reason: reason)
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
        keysWrittenHere.insert(key)
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

    func handleExternalChange(changedKeys: [String], reason: ExternalChangeReason) {
        switch reason {
        case .server:
            // Newer than what this device wrote, so a later download mustn't bring that back.
            keysWrittenHere.subtract(changedKeys)
            adopt(changedKeys)
        case .accountChange:
            keysWrittenHere.removeAll()
            adopt(changedKeys)
        case .initialSync:
            restoreWritesDiscardedByFirstDownload(changedKeys: changedKeys)
        }
    }

    private func adopt(_ keys: [String]) {
        for key in keys {
            mirror.set(cloud?.data(forKey: key), forKey: mirrorKey(key))
        }
        onExternalChange?(keys)
    }

    /// iCloud throws away what a device writes before its first download, which can come minutes
    /// after the first launch: a provider chosen in the meantime would silently go back to the
    /// on-device model. What the learner chose here is written again instead, and the download
    /// only brings what other devices saved.
    private func restoreWritesDiscardedByFirstDownload(changedKeys: [String]) {
        var adopted: [String] = []
        for key in changedKeys where !keysWrittenHere.contains(key) {
            let remote = cloud?.data(forKey: key)
            if remote == nil, let local = mirror.data(forKey: mirrorKey(key)) {
                // Written in an earlier launch that ended before the download.
                cloud?.set(local, forKey: key)
            } else {
                mirror.set(remote, forKey: mirrorKey(key))
                adopted.append(key)
            }
        }
        // Listed or not, since what the download reports isn't documented.
        for key in keysWrittenHere {
            let local = mirror.data(forKey: mirrorKey(key))
            guard cloud?.data(forKey: key) != local else { continue }
            if let local {
                cloud?.set(local, forKey: key)
            } else {
                cloud?.removeObject(forKey: key)
            }
        }
        if !adopted.isEmpty {
            onExternalChange?(adopted)
        }
    }

    private func mirrorKey(_ key: String) -> String { "vos.\(key)" }

    private func deviceKey(_ key: String) -> String { "vos.device.\(key)" }
}

/// Why iCloud changed values (`NSUbiquitousKeyValueStoreChangeReasonKey`).
enum ExternalChangeReason: Equatable {
    /// Another device changed them. Also used for the rare quota violation, and when no reason is
    /// given.
    case server
    /// iCloud's first download on this device replaced what was written before it.
    case initialSync
    /// The device signed in to another iCloud account.
    case accountChange

    init(code: Int?) {
        switch code {
        case NSUbiquitousKeyValueStoreInitialSyncChange?: self = .initialSync
        case NSUbiquitousKeyValueStoreAccountChange?: self = .accountChange
        default: self = .server
        }
    }
}
