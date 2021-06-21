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
    //0 = disabled
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
    case initialised
    case frameBufferRequest
    case readingFBRequestHeader
    case readingFBRectHeader
    case readingFBPixelData
    
    var isConnected: Bool { self.rawValue >= ConnectionState.initialisation.rawValue }
}

enum RFBError: Error {
    case alreadyConnecting
    case notConnected
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
    
    public func requestFrameBufferUpdate(incremental: Bool, x: UInt16, y: UInt16, width: UInt16, height: UInt16) throws {
        
        guard connectionState?.isConnected == true else { throw RFBError.notConnected }
        
        var info = [RFBMessageTypeClient.frameBufferRequest.rawValue]
        info.append(UInt8(truncating: incremental as NSNumber))
        info.append(contentsOf: x.bytes)
        info.append(contentsOf: y.bytes)
        info.append(contentsOf: width.bytes)
        info.append(contentsOf: height.bytes)
        
        if connectionState == .initialised {
            connectionState = .readingFBRequestHeader
        }
        
        outputStream?.write(bytes: info)
    }
    
    public func requestFullFrameBufferUpdate() throws {
        guard let bufferProcessor = bufferProcessor, let frameBuffer = bufferProcessor.frameBuffer, connectionState?.isConnected == true else {
            throw RFBError.notConnected
        }
        
        try requestFrameBufferUpdate(incremental: false, x: 0, y: 0, width: frameBuffer.width, height: frameBuffer.height)
    }
    
    public func sendPointerEvern(buttonMask: PointerButtons, location: (x: UInt16, y: UInt16)) throws {
        guard connectionState?.isConnected == true else {
            throw RFBError.notConnected
        }
        
        print("Send PointerEvent: \(location)")
        var info: [UInt8] = [RFBMessageTypeClient.pointerEvent.rawValue]
        info.append(buttonMask.rawValue)
        info.append(contentsOf: location.x.bytes)
        info.append(contentsOf: location.y.bytes)
        
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
            connectionState = .initialised
            delegate?.connectionEstablished(with: bufferProcessor!)
            
            if bufferProcessor?.delegate == nil {
                bufferProcessor?.delegate = self
            }
            
        case .initialised:
            print("unexpected server msg...")
            let type = inputStream?.readUInt8()
            print("HeaderType:", type)
            
        case .readingFBRequestHeader:
            print("ReadingRequestHeader")
            connectionState = .readingFBRectHeader
            bufferProcessor?.readHeader()
            
        case .readingFBRectHeader:
            print("ReadingRectHeader")
            if bufferProcessor?.readRectHeader() == true {
                connectionState = .readingFBPixelData
            } else {
                connectionState = .initialised
            }
            
        case .readingFBPixelData:
            print("ReadingPixelData")
            
            let result = bufferProcessor?.getPixelData()
            
            if  result == .readNextRect {
                print("ReadingRectHeader")
                connectionState = .readingFBRectHeader
            }
            else if result == .done {
                print("Image sent")
                connectionState = .initialised
            }
            
        default:
            print("Unknown state=", connectionState)
            return
        }
    }
}

extension RFBConnection: FrameBufferProcessorDelegate {
    public func didReceive(imageUpdate: PixelRectangle) {
        guard let image = imageUpdate.image else { return }
        delegate?.didReceive(image)
    }
}