//
//  File.swift
//  
//
//  Created by Henrik Storch on 16.06.21.
//

import Foundation
import CCryptoBoringSSL

/**
Errors that can occure during cipher operations
*/
public enum CipherError: Error {
    /**
    Occurs when some part of cipher proces fails
    
    - parameters reason: Error description
    */
    case cipherProcessFail(reason: String)
    
    /**
    Occurs when cipher key is invalid
    
    - parameters reason: Error description
    */
    case invalidKey(reason: String)
}

struct CipherErrorReason {
    static var openSSLError: String {
        return "OpenSSL Error: " + cryptoOpenSSLError()
    }
    
    static let cipherEncryption = #function + " Encryption Error - " + openSSLError
    static let cipherDecryption = #function + " Decryption Error - " + openSSLError
    
    static let cipherInit = #function + " Init Error - " + openSSLError
    static let cipherUpdate = #function + " Update Error - " + openSSLError
    static let cipherFinish = #function + " Finish Error - " + openSSLError
    
    static func cryptoOpenSSLError() -> String {
        CCryptoBoringSSL_ERR_load_crypto_strings()
        let err = UnsafeMutablePointer<CChar>.allocate(capacity: 130)
        CCryptoBoringSSL_ERR_error_string(CCryptoBoringSSL_ERR_get_error(), err)
        //print("ENC ERROR \(String(cString: err))")
    
        err.deinitialize(count: 130)
        err.deallocate()
        return String(cString: err)
    }
}
