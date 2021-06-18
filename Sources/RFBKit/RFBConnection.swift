//
//  RFBConnection.swift
//  
//
//  Created by Henrik Storch on 16.06.21.
//

import Foundation
import CoreGraphics

public protocol RFBConnectionDelegate {
    func didReceive(_ image: CGImage)
    func selectAuthentication(from authenticationTypes: [AuthenticationType]) -> AuthenticationType
    func authenticate(with authenticator: Authenticator)
    func connectionError()
    func authenticationError()
    func connectionEstablished(with processor: FrameBufferProcessor)
}

public struct PointerButtons: OptionSet {

    public let rawValue: UInt8
    
    public static let primary = PointerButtons(rawValue: 1 << 0)
    public static let middle = PointerButtons(rawValue: 1 << 1)
    public static let secondary = PointerButtons(rawValue: 1 << 2)
    public static let up = PointerButtons(rawValue: 1 << 3)
    public static let down = PointerButtons(rawValue: 1 << 4)
    public static let left = PointerButtons(rawValue: 1 << 5)
    public static let right = PointerButtons(rawValue: 1 << 6)
    public static let `let` = PointerButtons(rawValue: 1 << 7)
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}

public enum ConnectionState: Int {
    case protocolVersion
    case authenticationType
    case authenticating
    case receivingAuthenticationResponse
    case initialisation
    case readingRequestHeader
    case readingRectHeader
    case readingPixelData
}

enum RFBError: Error {
    case alreadyConnecting
    case badStream
}

public class RFBConnection: NSObject {
    public let host: String
    public let port: Int // = 5900
    
    public let shareFlag: Bool
    public var delegate: RFBConnectionDelegate?
    
    public init(host: String, port: Int = 5900, shouldDisconnectOthers shareFlag: Bool = false, delegate: RFBConnectionDelegate?) {
        self.host = host
        self.port = port
        self.shareFlag = shareFlag
        self.delegate = delegate
    }
    
    private static let rfbProtocol = "RFB 003.889\n"

    private(set) var connectionState: ConnectionState?
    
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    
    private var authenticator: Authenticator?
    private(set) var bufferProcessor: FrameBufferProcessor?
    
    public func connect() throws {
        guard connectionState == nil else {
            throw RFBError.alreadyConnecting
        }
        
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        let host: CFString = NSString(string: self.host)
        let port: UInt32 = UInt32(self.port)
        
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, host, port, &readStream, &writeStream)
        
        guard let readStream = readStream, let writeStream = writeStream else {
            throw RFBError.badStream
        }
        
        inputStream = readStream.takeRetainedValue()
        outputStream = writeStream.takeRetainedValue()
        
        inputStream!.delegate = self
        outputStream!.delegate = self
        
        inputStream!.schedule(in: RunLoop.main, forMode: .default)
        outputStream!.schedule(in: RunLoop.main, forMode: .default)
        inputStream!.open()
        outputStream!.open()
    }
    
    private func decideProtocolVersion() {
        guard inputStream != nil, outputStream != nil, connectionState == nil else {
            fatalError("No streams or bad state")
        }
        
        connectionState = .protocolVersion
        
        if let serverMsg = inputStream?.readString(maxLength: 128), !serverMsg.isEmpty {
            print("ServerProtocol:", serverMsg)
        } else {
            fatalError("serverMsg is empty")
        }
                
        outputStream?.write(string: RFBConnection.rfbProtocol)
    }
    
    private func selectAuth() {
        guard inputStream != nil, outputStream != nil, connectionState == .protocolVersion else {
            fatalError("No streams or bad state")
        }
        
        connectionState = .authenticationType
        
        guard let buffer = inputStream?.readBytes() else {
            print("No bytes read!")
            return
        }
        
        let typesCount = Int(buffer[0])
        let authenticationTypes = Array(buffer[1...typesCount])
        //30, 33, 36, 35
        print("AuthTypes=\(authenticationTypes)")
        
        let authTypes = AuthenticationType.factory(authenticationTypes: authenticationTypes)
        
        guard let selectedAuth = delegate?.selectAuthentication(from: authTypes),
              authTypes.contains(selectedAuth),
              let auther = selectedAuth.makeAuthenticator(inputStream: inputStream!, outputStream: outputStream!) else {
                  fatalError("Unsuported AuthType!")
                  return
              }
        
        self.authenticator = auther
        print("SelectedAuth=", selectedAuth)
        outputStream?.write(bytes: [selectedAuth.value])
    }
    
    public func sendPointerEvern(buttonMask: PointerButtons, location: (x: UInt16, y: UInt16)) {
        let x2 = UInt8(truncatingIfNeeded: location.x)
        let x1 = UInt8(truncatingIfNeeded: location.x.byteSwapped)
        let y2 = UInt8(truncatingIfNeeded: location.y)
        let y1 = UInt8(truncatingIfNeeded: location.y.byteSwapped)

        print("Send PointerEvent: \(location)")
        let info: [UInt8] = [UInt8(5), buttonMask.rawValue, x1, x2, y1, y2]
        outputStream?.write(info, maxLength: info.count)
    }
}

extension RFBConnection: StreamDelegate {
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case Stream.Event.openCompleted:
            print("OpenCompleted")
            
        case Stream.Event.errorOccurred:
            print("ErrorOccurred")
            delegate?.connectionError()
            connectionState = nil
#warning("Close connection??")
            
        case Stream.Event.hasBytesAvailable:
            print("HasBytesAvailiable")
            handleBytes(from: aStream)
            
//        case .hasSpaceAvailable:
//            print("didSend (aka hasSpaceAvailable)")
            
        case Stream.Event.endEncountered:
            print("Stream Endded, is input=", aStream == inputStream)
            
        default:
            break
//            print("Unknown stream event: \(eventCode), isOut=\(aStream == outputStream)")
        }
    }
    
    private func handleBytes(from aStream: Stream) {
        guard inputStream != nil && outputStream != nil, aStream == inputStream else {
            fatalError("Stream error..!?")
        }
        
        print(#function, connectionState)
        
        switch connectionState {
        case .none:
            decideProtocolVersion()
            
        case .protocolVersion:
            selectAuth()
            
        case .authenticationType:
            guard let auther = authenticator else {
                fatalError("No auther or bad state")
            }
            
            connectionState = .authenticating
            delegate?.authenticate(with: auther)
            
        case .authenticating:
            guard self.authenticator?.getAuthStatus() == .connected else {
                delegate?.authenticationError()
                return
            }
            
            outputStream!.write(bytes: [UInt8(truncating: true)])
            print("Auth OK")
            connectionState = .initialisation
            
        case .initialisation:
            bufferProcessor = FrameBufferProcessor(inputStream: inputStream, outputStream: outputStream)
            print("CONECTED!!")
            
            delegate?.connectionEstablished(with: bufferProcessor!)
        
        /*case .ReadingRequestHeader:
            NSLog("ReadingRequestHeader")
            currentState = state.ReadingRectHeader
            fBP!.readHeader()
            break
        case .ReadingRectHeader:
            NSLog("ReadingRectHeader")
            _ = fBP!.readRectHeader()
            currentState = state.ReadingPixelData
            
            break
        case .ReadingPixelData:
            NSLog("ReadingPixelData")
            if firstCon {
                Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(sendRequest), userInfo: nil, repeats: true)
                firstCon = false
            }
            let result = fBP!.getPixelData()
            if  result == 1 {
                NSLog("ReadingRectHeader")
                currentState = state.ReadingRectHeader
            }
            else if result == 2 {
                NSLog("ReadingRequestHeader")
                currentState = state.ReadingRequestHeader
            }
            break
         */
            
        default:
            print("Unknown state=", connectionState)
            return
        }
    }
}
