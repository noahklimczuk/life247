//
//  KeychainHelper.swift
//  life247
//

import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}
    
    func save(_ data: Data, service: String, account: String) {
        // Clear old instance to avoid duplicate items conflicts
        let deleteQuery = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as [String: Any]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Define exact explicit storage requirements
        let saveQuery = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ] as [String: Any]
        
        let status = SecItemAdd(saveQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("⚠️ Keychain save error status log: \(status)")
        }
    }
    
    func read(service: String, account: String) -> Data? {
        // Enforce kCFBooleanTrue to guarantee memory reference population
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any, // Crucial for reliable bridging
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as [String: Any]
        
        var dataTypeRef: AnyObject?
        let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            return dataTypeRef as? Data
        }
        return nil
    }
    
    func delete(service: String, account: String) {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ] as [String: Any]
        SecItemDelete(query as CFDictionary)
    }
}
