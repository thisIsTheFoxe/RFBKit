//
//  Authenticator.swift
//  
//
//  Created by Henrik Storch on 16.06.21.
//

import Foundation
import Crypto

/// A RFB [security type](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#security-types)
public enum AuthenticationType: Equatable {
    public var value: UInt8 {
        switch self {
        case .invalid:          return 0
        case .none:             return 1
        case .vncAuth:          return 2
        case .ard:              return 30
        case .appleKDC:         return 35
        case let .other(value): return value
        }
    }
    
    case invalid
    
    /// No authentication is needed
    case none
    
    /// Using a 16-byte challenge
    case vncAuth
    
    /// Apple Remote Desktop uses login & password with a DH key exchange
    case ard
    
    ///Apple Key Distribution Center (Kerberos)
    /// - See Also:  [This Gist](https://gist.github.com/zoocoup/4069441)
    case appleKDC
    
    /// Any other security type
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
    
    /// Creates a list of `AuthenticationType` from a byte array
    /// - Parameter authenticationTypes: The byte array
    /// - Returns: List of `AuthenticationType`s
    static func factory(authenticationTypes: [UInt8]) -> [AuthenticationType] {
        authenticationTypes.map(AuthenticationType.init)
    }
    
    /// Creats an `Authenticator` that handles the the security type
    /// - Parameters:
    ///   - inputStream: The input stream of the RFB connection
    ///   - outputStream: The output stream of the RFB connection
    /// - Returns: Type specific `Authenticator` if available
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
}

/// The status of an RFB authentication
public enum AuthenticationStatus: Int {
    case connected = 0, wrongPassword = 1, tooManyAttemts = 2, unknown = 255
}

/// A type that can be authenticated
public protocol Authenticatable {
    /// Checks the current authentication status
    /// - Returns: The current `AuthenticationStatus`
    func getAuthStatus() -> AuthenticationStatus
}

/// A type that handles authenticatin
internal protocol Authenticator: Authenticatable {
    /// RFB input stream
    var inputStream: InputStream { get }


    /// RFB output stream
    var outputStream: OutputStream { get }
}

extension Authenticator {
    public func getAuthStatus() -> AuthenticationStatus {
        guard let result = inputStream.readUInt32(),
              let status = AuthenticationStatus(rawValue: Int(result))
        else { return .unknown }
        
        return status
    }
}

///[UNTESTED]
/// 'Handles' the *None* security-type
///
/// **Version 3.8 onwards**
/// The protocol continues with the SecurityResult message.
///
/// **Version 3.3 and 3.7**
/// The protocol passes to the initialisation phase (Initialisation Messages).
public class NoneAuthenticator: Authenticator {
    internal init(inputStream: InputStream, outputStream: OutputStream) {
        self.inputStream = inputStream
        self.outputStream = outputStream
    }
    
    var inputStream: InputStream
    var outputStream: OutputStream
}

///[UNTESTED]
/// An `Authenticator` that handles VNC authentication
public class VNCAuthenticator: Authenticator {
    
    internal let inputStream: InputStream
    internal let outputStream: OutputStream
    
    internal init(inputStream: InputStream, outputStream: OutputStream) {
        self.inputStream = inputStream
        self.outputStream = outputStream
    }
    
    /// Reverses the bits in a `String`
    ///
    /// - Note: The lowest bit of each byte is considered the first bit and the highest discarded as parity. This is the reverse order of most implementations of DES so the key may require adjustment to give the expected result.
    ///
    /// - Parameter password: The `String` to reverse
    /// - Returns: The reversed `String` as `Data`
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
    
    /// Handles VNC authentication
    /// - Parameter password: The VNC password
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

/// An error that occured while authenticating using ARD
enum ARDError: Error {
    case noSharedSecret, noPublicKey
}

/// An `Authenticator` that handles Apple Remote Desktop authentication
public class AppleAuthenticator: Authenticator {
    internal let inputStream: InputStream
    internal let outputStream: OutputStream
    
    internal init(inputStream: InputStream, outputStream: OutputStream) {
        self.inputStream = inputStream
        self.outputStream = outputStream
    }
    
    /// Handle RFB authentication
    /// - Parameters:
    ///   - username: Username or Login
    ///   - password: User's password
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
