import Foundation
import os
import Security
import Synchronization
import VocabularyCore

public enum SecretStoreError: Error, Equatable, Sendable, LocalizedError {
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            String(localized: "The key couldn't be stored in the Keychain (error \(status)).", bundle: .module)
        }
    }
}

/// Where API keys live: only the Keychain in the app (ADR-002, ADR-003). Accounts are provider IDs.
public protocol SecretStore: Sendable {
    func secret(for account: String) throws(SecretStoreError) -> String?
    /// Saves the secret; `nil` or a blank string deletes it.
    func setSecret(_ value: String?, for account: String) throws(SecretStoreError)
}

/// Keeps secrets in memory; for tests and previews.
public final class InMemorySecretStore: SecretStore {
    private let values = Mutex<[String: String]>([:])

    public init() {}

    public func secret(for account: String) throws(SecretStoreError) -> String? {
        values.withLock { $0[account] }
    }

    public func setSecret(_ value: String?, for account: String) throws(SecretStoreError) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        values.withLock { $0[account] = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }
}

/// Generic-password items in the Keychain (ADR-002).
///
/// Signed builds sync keys through iCloud Keychain and share them with the Share extension through the
/// App Group access group. Unsigned builds lack those entitlements; the Keychain then answers
/// `errSecMissingEntitlement`, and the store falls back to a local item so keys still work on that
/// device.
public struct KeychainSecretStore: SecretStore {
    private let service: String
    private let accessGroup: String?
    private let synchronizes: Bool
    private let logger = Logger(subsystem: VocabularyCore.logSubsystem, category: VocabularyAI.logCategory)

    public init(service: String = "app.vocabularyos.api-keys", accessGroup: String?, synchronizes: Bool = true) {
        self.service = service
        self.accessGroup = accessGroup
        self.synchronizes = synchronizes
    }

    public func secret(for account: String) throws(SecretStoreError) -> String? {
        for attributes in attributeVariants(for: account) {
            var query = attributes
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess:
                guard let data = result as? Data else { return nil }
                return String(data: data, encoding: .utf8)
            case errSecItemNotFound, errSecMissingEntitlement:
                continue
            default:
                throw .keychain(status)
            }
        }
        return nil
    }

    public func setSecret(_ value: String?, for account: String) throws(SecretStoreError) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for attributes in attributeVariants(for: account) {
            let status = SecItemDelete(attributes as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement else {
                throw .keychain(status)
            }
        }
        guard !trimmed.isEmpty else { return }

        var lastStatus = errSecSuccess
        for attributes in attributeVariants(for: account) {
            var item = attributes
            item[kSecValueData as String] = Data(trimmed.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            lastStatus = SecItemAdd(item as CFDictionary, nil)
            if lastStatus == errSecSuccess { return }
            guard lastStatus == errSecMissingEntitlement else { break }
            logger.notice("Keychain entitlement missing; storing the API key on this device only")
        }
        throw .keychain(lastStatus)
    }

    /// The full item first (synced, shared), then a local fallback for builds without entitlements.
    func attributeVariants(for account: String) -> [[String: Any]] {
        var base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        base[kSecUseDataProtectionKeychain as String] = true
        #endif
        var full = base
        if let accessGroup {
            full[kSecAttrAccessGroup as String] = accessGroup
        }
        full[kSecAttrSynchronizable as String] = synchronizes ? kCFBooleanTrue : kCFBooleanFalse

        var local = base
        local[kSecAttrSynchronizable as String] = kCFBooleanFalse
        #if os(macOS)
        // Ad-hoc signed builds can't use the data protection keychain at all, so they fall back to
        // the login keychain. Signed builds, which have the App Group, never look there: any app
        // could have put an item there under our service name (security review).
        local[kSecUseDataProtectionKeychain as String] = nil
        return accessGroup == nil ? [full, local] : [full]
        #else
        // Without a group or sync, the two variants are the same item.
        return accessGroup == nil && !synchronizes ? [full] : [full, local]
        #endif
    }
}
