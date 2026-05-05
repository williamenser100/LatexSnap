import Foundation
import Security

struct KeychainHelper {
    private static let service = "com.latexsnap.app"
    private static let account = "anthropic-api-key"

    static var apiKey: String? {
        get {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne
            ]
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            if let value = newValue, !value.isEmpty {
                guard let data = value.data(using: .utf8) else { return }
                let query: [CFString: Any] = [
                    kSecClass: kSecClassGenericPassword,
                    kSecAttrService: service,
                    kSecAttrAccount: account
                ]
                let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
                if status == errSecItemNotFound {
                    SecItemAdd(query.merging([kSecValueData: data]) { $1 } as CFDictionary, nil)
                }
            } else {
                let query: [CFString: Any] = [
                    kSecClass: kSecClassGenericPassword,
                    kSecAttrService: service,
                    kSecAttrAccount: account
                ]
                SecItemDelete(query as CFDictionary)
            }
        }
    }
}
