//
//  EntryEncryption.swift
//  DailyJournal
//

import CryptoKit
import Foundation

enum EntryEncryption {

    private static let keychainKey = "com.ninety.entryEncryptionKey"

    private static var cachedKey: SymmetricKey?

    static func key() -> SymmetricKey {
        if let cached = cachedKey { return cached }
        if let data = KeychainHelper.load(forKey: keychainKey),
           data.count == 32 {
            let k = SymmetricKey(data: data)
            cachedKey = k
            return k
        }
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        KeychainHelper.save(keyData, forKey: keychainKey)
        cachedKey = newKey
        return newKey
    }

    static func encrypt(_ plaintext: String) -> String? {
        guard !plaintext.isEmpty else { return "" }
        let data = Data(plaintext.utf8)
        guard let sealed = try? AES.GCM.seal(data, using: key()) else { return nil }
        return sealed.combined?.base64EncodedString()
    }

    static func decrypt(_ ciphertext: String) -> String? {
        guard !ciphertext.isEmpty else { return "" }
        guard let data = Data(base64Encoded: ciphertext),
              let box = try? AES.GCM.SealedBox(combined: data),
              let decrypted = try? AES.GCM.open(box, using: key())
        else { return nil }
        return String(data: decrypted, encoding: .utf8)
    }
}
