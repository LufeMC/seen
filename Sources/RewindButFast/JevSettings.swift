import SwiftUI
import Security
import RewindCore

struct APIKeyStore {
    var service = "local.rewindbutfast.app.jev"
    private func query(_ provider: JevProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }
    func read(_ provider: JevProvider) throws -> String? {
        var attributes = query(provider)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw KeyError(status: status)
        }
        return key
    }
    func save(_ key: String, provider: JevProvider) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw JevError.missingKey }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(provider) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(provider)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let inserted = SecItemAdd(attributes as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw KeyError(status: inserted) }
        } else if status != errSecSuccess { throw KeyError(status: status) }
    }
    func remove(_ provider: JevProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError(status: status) }
    }
    private struct KeyError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Keychain could not complete the action (\(status))." }
    }
}

struct JevSettingsSection: View {
    @Bindable var model: AppModel
    @State private var key = ""
    @State private var message = ""
    var body: some View {
        Section("Optional Jev search") {
            Picker("Provider", selection: $model.jevProvider) {
                ForEach(JevProvider.allCases) { Text($0.name).tag($0) }
            }
            SecureField("Your API key", text: $key)
            HStack {
                Button("Save key") {
                    do { try APIKeyStore().save(key, provider: model.jevProvider); key = ""; message = "Key saved. Jev search is now automatic."; model.refreshJevConfiguration() }
                    catch { message = error.localizedDescription }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove saved key") {
                    do { try APIKeyStore().remove(model.jevProvider); key = ""; message = "Saved key removed. Local search remains available."; model.refreshJevConfiguration() }
                    catch { message = error.localizedDescription }
                }
            }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            Text("With a saved key, searches automatically send your query, app names, titles, and text from up to 32 captures to this provider. Images stay on your Mac.")
                .foregroundStyle(.secondary)
            Text("Saving a key enables automatic Jev search. Provider charges and data policies apply. Remove the key to use local search only.")
                .foregroundStyle(.secondary)
            Link("TypeSafe API keys", destination: URL(string: "https://typesafe.ai")!)
            Link("Vercel AI Gateway keys", destination: URL(string: "https://vercel.com/docs/ai-gateway/authentication-and-byok/authentication")!)
        }.onChange(of: model.jevProvider) { key = ""; message = "" }
    }
}

struct JevSearchStatus: View {
    let busy: Bool
    let status: String?
    var body: some View {
        if busy || status != nil {
            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.mini) }
                Text(busy ? "Searching with Jev…" : (status ?? ""))
                    .foregroundStyle(Style.secondary).lineLimit(2)
                Spacer(minLength: 0)
            }.font(Style.small)
        }
    }
}
