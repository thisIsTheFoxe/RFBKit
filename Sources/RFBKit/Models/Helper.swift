//
//  Helper.swift
//  
//
//  Created by Henrik Storch on 16.06.21.
//

import Foundation
import Foundation
import var CommonCrypto.CC_MD5_DIGEST_LENGTH
import func CommonCrypto.CC_MD5
import typealias CommonCrypto.CC_LONG
import Crypto



extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}


public extension UnsignedInteger {
    init(_ bytes: [UInt8]) {
        precondition(bytes.count <= MemoryLayout<Self>.size)
        
        var value: UInt64 = 0
        
        for byte in bytes {
            value <<= 8
                        value |= UInt64(byte)
        }
        
        self.init(value)
    }
}


extension Data {
    
    func makeUInt8DataPointer() -> UnsafeMutablePointer<UInt8> {
        let dataPointer = UnsafeMutablePointer<UInt8>(mutating: (self as NSData).bytes.bindMemory(to: UInt8.self, capacity: self.count))
        return dataPointer
    }
    
    func makeInt8DataPointer() -> UnsafeMutablePointer<Int8> {
        let dataPointer = UnsafeMutablePointer<Int8>(mutating: (self as NSData).bytes.bindMemory(to: Int8.self, capacity: self.count))
        return dataPointer
    }
    
    static func makeUInt8EmptyArray(ofSize size: Int) -> [UInt8] {
        return [UInt8](repeating: UInt8(), count: size)
    }
    
//    public func hexEncodedString() -> String {
//        return map { String(format: "%02hhx", $0) }.joined()
//    }
    
    public func md5() -> Data {
        Insecure.MD5.hash(data: self).reduce(into: Data()) { partialResult, next in
            partialResult.append(next)
        }
    }
}
