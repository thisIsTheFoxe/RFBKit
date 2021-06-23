//
//  DES.swift
//  
//
//  Created by Henrik Storch on 22.06.21.
//

import Foundation
import CommonCrypto

struct DESOptions: OptionSet {
    var rawValue: Int
    
    init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static var ecbMode = DESOptions(rawValue: kCCOptionECBMode)
    public static var pkcs7Padding = DESOptions(rawValue: kCCOptionPKCS7Padding)
}

enum DESError: Error {
    case operationFailed
}

class DES: NSObject {
    static func encrypt(_ input: Data, with key: Data, options: DESOptions) throws -> Data  {
        
        let keyLength       = kCCKeySizeDES
        var bufferData      = Data(count: input.count + kCCBlockSizeDES)
        var bytesEncrypted  = 0
        var status          = CCCryptorStatus(0)
        
        // Perform operation
        key.withUnsafeBytes { keyBytes in
            input.withUnsafeBytes { inputBytes in
                bufferData.withUnsafeMutableBytes { bufferBytes in
                    status = CCCrypt(
                        CCOperation(kCCEncrypt),                  // Operation
                        CCAlgorithm(kCCAlgorithmDES),    // Algorithm
                        CCOptions(options.rawValue),  // Options
                        keyBytes.baseAddress!,      // key data
                        keyLength,                  // key length
                        nil,        // IV buffer
                        inputBytes.baseAddress!,    // input data
                        inputBytes.count,           // input length
                        bufferBytes.baseAddress,    // output buffer
                        bufferBytes.count,          // output buffer length
                        &bytesEncrypted             // output bytes decrypted real length
                    )
                }
            }
        }
        
        if (status == kCCSuccess) {
            bufferData.count = bytesEncrypted // Adjust buffer size to real bytes
            return bufferData
        } else {
            print("[ERROR] failed to encrypt|CCCryptoStatus:", status)
        }
        
        throw DESError.operationFailed
    }
}
