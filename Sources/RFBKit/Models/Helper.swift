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
    /// Clamps a value between two bounds
    /// - Parameter limits: The range of allowed values
    /// - Returns: The clamped value
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

public extension SignedInteger {
    /// Initializes a `SignedInteger` using raw bytes.
    ///
    /// - Precondition: The number of `bytes` cannot be higher than the space available to store the number.
    ///
    /// ```
    /// let number = Int32([255, 0xFF, 0b11111111, 254])
    /// print(number)
    /// // prints "Optional(-2)"
    /// ```
    ///
    /// - Parameter bytes: The byte representaion of the number
    init(_ bytes: [UInt8]) {
        precondition(bytes.count <= MemoryLayout<Self>.size)
        
        var value: Int64 = 0
        
        for byte in bytes {
            value <<= 8
            value |= Int64(byte)
        }
        
        self.init(value)
    }
}

public extension UnsignedInteger {
    /// Initializes a `UnsignedInteger` using raw bytes. It fails with
    ///
    /// - Precondition: The number of `bytes` cannot be higher than the space available to store the number.
    ///
    /// ```
    /// let number = UInt16([0b10000000, 0x0A])
    /// print(number)
    /// // prints "Optional(32778)"
    /// ```
    ///
    /// - Parameter bytes: The byte representaion of the number
    init(_ bytes: [UInt8]) {
        precondition(bytes.count <= MemoryLayout<Self>.size)
        
        var value: UInt64 = 0
        
        for byte in bytes {
            value <<= 8
            value |= UInt64(byte)
        }
        
        self.init(value)
    }
    
    /// The byte representation of the number
    var bytes: [UInt8] {
        var result = [UInt8]()
        
        var value = self
        
        for _ in 0..<MemoryLayout<Self>.size {
            result.append(UInt8(truncatingIfNeeded: value))
            value >>= 8
        }
        
        return result.reversed()
    }
}


extension Data {
    
    /// Turns raw data into a raw data pointer
    ///
    /// Used for Diffie–Hellman algorithm in `DHCore`
    ///
    /// - Returns: The data pointer
    func makeUInt8DataPointer() -> UnsafeMutablePointer<UInt8> {
        let dataPointer = UnsafeMutablePointer<UInt8>(
            mutating: (self as NSData).bytes.bindMemory(
                to: UInt8.self,
                capacity: self.count))
        return dataPointer
    }
    
    /// Turns raw data into a raw data pointer
    ///
    /// Used for Diffie–Hellman algorithm in `DHCore`
    ///
    /// - Returns: The data pointer
    func makeInt8DataPointer() -> UnsafeMutablePointer<Int8> {
        let dataPointer = UnsafeMutablePointer<Int8>(
            mutating: (self as NSData).bytes.bindMemory(
                to: Int8.self,
                capacity: self.count))
        return dataPointer
    }
    
    
    /// Initializes a empty byte array with zeroes
    /// - Parameter size: The number of bytes
    /// - Returns: The empty byte array
    static func makeUInt8EmptyArray(ofSize size: Int) -> [UInt8] {
        return [UInt8](repeating: UInt8(), count: size)
    }
    
    
    /// Calculates the md5 hash of the data
    /// - Returns: The md5 hash as raw data
    public func md5() -> Data {
        Insecure.MD5.hash(data: self).reduce(into: Data()) { partialResult, next in
            partialResult.append(next)
        }
    }
}
