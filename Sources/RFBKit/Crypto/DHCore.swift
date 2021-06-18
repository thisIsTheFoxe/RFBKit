//
//  DHCore.swift
//  
//
//  Created by Henrik Storch on 16.06.21.
//

import Foundation
import CCryptoBoringSSL

class DiffieHellmanCore: NSObject {
    
    var dhKey: UnsafeMutablePointer<DH>?
    
//    var publicKey: String? {
//        return extractPublicKey()
//    }

    var publicKey: Data? {
        return extractPublicKey()
    }
    
    var p: String? {
        return extractParameterP()
    }
    
    var g: String? {
        return extractParameterG()
    }
    
    init(p: String, g: String) {
        super.init()
        generateKey(p: p, g: g)
    }

    init(p: Data, g: Data) {
        super.init()
        generateKey(p: p, g: g)
    }
    
    init(primeLength: Int) {
        super.init()
        dhKey = generateKey(primeLen: primeLength)
    }

    func generateKey(p pValue: Data, g gValue: Data) {
        dhKey = CCryptoBoringSSL_DH_new()
        
        
        
        let bnP = CCryptoBoringSSL_BN_new()
        let pData = pValue.makeUInt8DataPointer()
        let pPointer = UnsafePointer<UInt8>(pData)
        let bigP = CCryptoBoringSSL_BN_bin2bn(pPointer, pValue.count, bnP)
        
        let bnG = CCryptoBoringSSL_BN_new()
        let gData = gValue.makeUInt8DataPointer()
        let gPointer = UnsafePointer<UInt8>(gData)
        let bigG = CCryptoBoringSSL_BN_bin2bn(gPointer, gValue.count, bnG)
        
        dhKey!.pointee.p = bigP
        dhKey!.pointee.g = bigG
        
        let result = CCryptoBoringSSL_DH_generate_key(dhKey!)
        print("DH_generate_key=", result)
    }
    
    func generateKey(p pValue: String, g gValue: String) {
        dhKey = CCryptoBoringSSL_DH_new()
        
        var bnP = CCryptoBoringSSL_BN_new()
        let pData = pValue.data(using: .utf8)?.makeInt8DataPointer()
        let pPointer = UnsafePointer<Int8>(pData)
        CCryptoBoringSSL_BN_hex2bn(&bnP, pPointer!)
        
        var bnG = CCryptoBoringSSL_BN_new()
        let gData = gValue.data(using: .utf8)?.makeInt8DataPointer()
        let gPointer = UnsafePointer<Int8>(gData)
        CCryptoBoringSSL_BN_hex2bn(&bnG, gPointer!)
        
        dhKey!.pointee.p = bnP
        dhKey!.pointee.g = bnG
        
        CCryptoBoringSSL_DH_generate_key(dhKey!)
    }
    
    func generateKey(primeLen len: Int) -> UnsafeMutablePointer<DH>? {
        var key: UnsafeMutablePointer<DH>!
        
        CCryptoBoringSSL_DH_generate_parameters_ex(key, Int32(len), 2, nil)
        
        if key != nil {
            CCryptoBoringSSL_DH_generate_key(key)
            return key
        }
        return nil
    }
    
    func computeKey(withPublicKey pk: Data) -> Data? {
        if let dhKey = dhKey {
            let size = CCryptoBoringSSL_DH_size(dhKey)
            var computedKey = Data.makeUInt8EmptyArray(ofSize: Int(size))
            
            let bnG = CCryptoBoringSSL_BN_new()
            let gData = pk.makeUInt8DataPointer()
            let gPointer = UnsafePointer<UInt8>(gData)
            CCryptoBoringSSL_BN_bin2bn(gPointer, Int(size), bnG)
            
            CCryptoBoringSSL_DH_compute_key(&computedKey, bnG, dhKey)
            return Data(computedKey)
        }
        return nil
    }
    
    func extractPublicKey() -> Data? {
        if let dhKey = dhKey, let bnP = dhKey.pointee.pub_key {
            #warning("Constant! Should be infered...")
            var data = [UInt8](Data(count: Int(128)))
            
            CCryptoBoringSSL_BN_bn2bin(bnP, &data)
            
            return Data(data)
        }
        return nil
    }
    
//    func extractPublicKey() -> String? {
//        if let dhKey = dhKey {
//            let bnP = dhKey.pointee.pub_key
//            
//            if let pData = CCryptoBoringSSL_BN_bn2hex(bnP) {
//                if let p = String(utf8String: pData) {
//                    return String(describing: p)
//                }
//            }
//        }
//        return nil
//    }
    
    func extractParameterP() -> String? {
        if let dhKey = dhKey {
            let bnP = dhKey.pointee.p
            
            if let pData = CCryptoBoringSSL_BN_bn2hex(bnP) {
                if let p =  String(utf8String: pData) {
                    return String(describing: p)
                }
            }
        }
        return nil
    }
    
    func extractParameterG() -> String? {
        if let dhKey = dhKey {
            let bnG = dhKey.pointee.g
            
            if let gData = CCryptoBoringSSL_BN_bn2hex(bnG) {
                if let g =  String(utf8String: gData) {
                    return String(describing: g)
                }
            }
        }
        return nil
    }
}
