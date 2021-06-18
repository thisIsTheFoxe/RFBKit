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
        case .ard: return 30
        case .vncAuth: return 2
        case let .other(value): return value
        }
    }
    
    case ard
    case vncAuth
    case other(UInt8)
    
    init(value: UInt8) {
        switch value {
        case 30: self = .ard
        case 2: self = .vncAuth
        default:
            self = .other(value)
        }
    }
    
    func makeAuthenticator(inputStream: InputStream, outputStream: OutputStream) -> Authenticator? {
        switch self {
        case .ard:
            return AppleAuthenticator(inputStream: inputStream, outputStream: outputStream)
        case .vncAuth:
            return VNCAuthenticator(inputStream: inputStream, outputStream: outputStream)
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

public protocol Authenticator {
    func getAuthStatus() -> AuthenticationStatus
}

public class AppleAuthenticator: Authenticator {
    internal let inputStream: InputStream
    internal let outputStream: OutputStream
    
    internal init(inputStream: InputStream, outputStream: OutputStream) {
        self.inputStream = inputStream
        self.outputStream = outputStream
    }
    
    public func authenticate(username: String, password: String) {
        guard inputStream.hasBytesAvailable else { fatalError("No bytes to atuhenticate!") }
        
        guard let generator = inputStream.readData(maxLength: 2),
              let keyLength = inputStream.readUInt16(),
              let primeMod = inputStream.readData(maxLength: Int(keyLength)),
              let serverPubKey = inputStream.readData(maxLength: Int(keyLength)) else {
                  fatalError("Error reading server data")
              }
        
        print("Auth parameters set")
        
        let dh = DiffieHellman(p: primeMod, g: generator)
        guard let sharedSecret = dh.computeSharedSecret(withPublicKey: serverPubKey), let publicKey = dh.publicKey else {
            return
            //throws
        }
        
        print("secret / pubKey", sharedSecret.base64EncodedString(), publicKey.base64EncodedString())
        
        var credData = Data(username.utf8) + Data(count: 1)
        while credData.count < 64 {
            credData.append(UInt8.random(in: 0...255))
        }
        credData.append(Data(password.utf8))
        credData.append(Data(count: 1))
        while credData.count < 128 {
            credData.append(UInt8.random(in: 0...255))
        }
        
        print("CredData ClearTxt: ", credData.base64EncodedString())
        
        let encKey = sharedSecret.md5()
        print("encMD5:", encKey.base64EncodedString())
        
        do {
            let cypher = try AESCipher(key: encKey, iv: Data(), blockMode: .ecb)
            let encCred = try cypher.encrypt(data: credData)
            
            let response = encCred + publicKey
            print("sending", response)
            outputStream.write(data: response)
            
        } catch {
            print("err:", error.localizedDescription)
        }
    }
    
    public func getAuthStatus() -> AuthenticationStatus {
        guard let result = inputStream.readUInt32(), let status = AuthenticationStatus(rawValue: Int(result)) else {
            return .unknown
        }
        
        return status
    }
}

public class VNCAuthenticator: Authenticator {
    public func getAuthStatus() -> AuthenticationStatus {
        return .connected
    }
    
    internal let inputStream: InputStream
    internal let outputStream: OutputStream
    
    internal init(inputStream: InputStream, outputStream: OutputStream) {
        self.inputStream = inputStream
        self.outputStream = outputStream
    }
    
    public func authenticate(username: String?, password: String?) {
        
    }
}
