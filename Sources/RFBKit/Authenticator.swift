//
//  Authenticator.swift
//  
//
//  Created by Henrik Storch on 16.06.21.
//

import Foundation
import Crypto

public enum AuthenticationType: Equatable {
    public var value: UInt8 {
        switch self {
        case .invalid:          return 0
        case .none:             return 1
        case .vncAuth:          return 2
        case .ard:              return 30
            ///Apple Key Distribution Center (Kerberos)
            ///see https://gist.github.com/zoocoup/4069441
        case .appleKDC:         return 35
        case let .other(value): return value
        }
    }
    
    case invalid
    case none
    case vncAuth
    case ard
    case appleKDC
    case other(UInt8)
    
    init(value: UInt8) {
        switch value {
        case 0: self = .invalid
        case 1: self = .none
        case 2: self = .vncAuth
        case 30: self = .ard
        case 35: self = .appleKDC
        default:
            self = .other(value)
        }
    }
    
    func makeAuthenticator(inputStream: InputStream, outputStream: OutputStream) -> Authenticator? {
        switch self {
        case .invalid:
            return nil
        case .none:
            return NoneAuthenticator(inputStream: inputStream, outputStream: outputStream)
        case .vncAuth:
            return VNCAuthenticator(inputStream: inputStream, outputStream: outputStream)
        case .ard:
            return AppleAuthenticator(inputStream: inputStream, outputStream: outputStream)
        case .appleKDC:
            return nil
        case .other(let uInt8):
            print("No Authenticator available for: \(uInt8)")
            return nil
        }
    }
    
    static func factory(authenticationTypes: [UInt8]) -> [AuthenticationType] {
        authenticationTypes.map(AuthenticationType.init)
    }
}

public enum AuthenticationStatus: Int {
    case connected = 0, wrongPassword = 1, tooManyAttemts = 2, unknown = 255
}

public protocol Authenticatable {
    func getAuthStatus() -> AuthenticationStatus
}

internal protocol Authenticator: Authenticatable {
    var inputStream: InputStream { get }
    var outputStream: OutputStream { get }
}

extension Authenticator {
    public func getAuthStatus() -> AuthenticationStatus {
        guard let result = inputStream.readUInt32(), let status = AuthenticationStatus(rawValue: Int(result)) else {
            return .unknown
        }
        
        return status
    }
}

enum ARDError: Error {
    case noSharedSecret, noPublicKey
}

public class AppleAuthenticator: Authenticator {
    internal let inputStream: InputStream
    internal let outputStream: OutputStream
    
    internal init(inputStream: InputStream, outputStream: OutputStream) {
        self.inputStream = inputStream
        self.outputStream = outputStream
    }
    
    public func authenticate(username: String, password: String) throws {
        
        guard inputStream.hasBytesAvailable,
              let generator = inputStream.readData(maxLength: 2),
              let keyLength = inputStream.readUInt16(),
              let primeMod = inputStream.readData(maxLength: Int(keyLength)),
              let serverPubKey = inputStream.readData(maxLength: Int(keyLength)) else {
                  throw RFBError.badStream
              }
        
        let dh = DiffieHellman(p: primeMod, g: generator)
        
        guard let sharedSecret = dh.computeSharedSecret(withPublicKey: serverPubKey) else {
            throw ARDError.noSharedSecret
        }
        
        guard let publicKey = dh.publicKey else { throw ARDError.noPublicKey }
        
        var credData = Data(username.utf8) + Data(count: 1)
        while credData.count < 64 {
            credData.append(UInt8.random(in: 0...255))
        }
        credData.append(Data(password.utf8))
        credData.append(Data(count: 1))
        while credData.count < 128 {
            credData.append(UInt8.random(in: 0...255))
        }
        
        let encKey = sharedSecret.md5()
        
        let cypher = try AESCipher(key: encKey, iv: Data(), blockMode: .ecb)
        let encCred = try cypher.encrypt(data: credData)
        
        let response = encCred + publicKey
        
        outputStream.write(data: response)
    }
}

///[UNTESTED]
public class VNCAuthenticator: Authenticator {
    
    internal let inputStream: InputStream
    internal let outputStream: OutputStream
    
    internal init(inputStream: InputStream, outputStream: OutputStream) {
        self.inputStream = inputStream
        self.outputStream = outputStream
    }
    
    private func reverseBits(in password: String) -> Data {
        var result = Data()
        let pwBytes = [UInt8](password.utf8)
        
        for i in 0..<8 {
            if i < pwBytes.count {
                var byte = pwBytes[i]
                byte = (byte & 0xF0) >> 4 | (byte & 0x0F) << 4
                byte = (byte & 0xCC) >> 2 | (byte & 0x33) << 2
                byte = (byte & 0xAA) >> 1 | (byte & 0x55) << 1
                result.append(byte)
            } else {
                result.append(0)
            }
        }
        
        return result
    }
    
    public func authenticate(password: String) throws {
//        assert inputStream.readInt32() == 2 aka VNC Auth type (?), for older versions mby...
        guard let challenge = inputStream.readData(maxLength: 16) else {
            throw RFBError.badStream
        }
        let key = reverseBits(in: password)
        
        //Each 8 bytes of the challenge is encrypted independently (i.e. ECB mode) and sent back to the server
        let c1 = challenge[..<8]
        let c2 = challenge[8...]
        
        let enc1 = try DES.encrypt(c1, with: key, options: [.pkcs7Padding, .ecbMode])
        let enc2 = try DES.encrypt(c2, with: key, options: [.pkcs7Padding, .ecbMode])
        
        let result = enc1 + enc2
        
        outputStream.write(data: result)
    }
}

///[UNTESTED]
public class NoneAuthenticator: Authenticator {
    internal init(inputStream: InputStream, outputStream: OutputStream) {
        self.inputStream = inputStream
        self.outputStream = outputStream
    }
    
    var inputStream: InputStream
    var outputStream: OutputStream
}
