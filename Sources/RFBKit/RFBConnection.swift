//
//  RFBConnection.swift
//  
//
//  Created by Henrik Storch on 16.06.21.
//

import Foundation
import CoreGraphics

/// A delegate to notify about connection changes / updates
public protocol RFBConnectionDelegate {
    /// The frame buffer updated the image
    func didReceive(_ image: CGImage)
    
    /// Select a authentication type from a list of security-types provided by the server
    /// - Returns: The selected type
    func selectAuthentication(from authenticationTypes: [AuthenticationType]) -> AuthenticationType
    
    /// Handle RFB authentication
    func authenticate(with authenticator: Authenticatable)
    
    /// A connection error occured
    func connectionError(reason: String?)
    
    /// An authentication error occured
    func authenticationError()
    
    /// The RFB connection was established successfully
    func connectionEstablished(with processor: FrameBufferProcessor)
}

/// Types of mouse / trackpad buttons
public struct PointerButtons: OptionSet {

    public let rawValue: UInt8
    //0 = disabled
    public static let primary = PointerButtons(rawValue: 1 << 0)
    public static let secondary = PointerButtons(rawValue: 1 << 1)
//    public static let mouseWheel = PointerButtons(rawValue: 1 << 2)
    public static let up = PointerButtons(rawValue: 1 << 3)
    public static let down = PointerButtons(rawValue: 1 << 4)
    public static let left = PointerButtons(rawValue: 1 << 5)
    public static let right = PointerButtons(rawValue: 1 << 6)
    public static let `let` = PointerButtons(rawValue: 1 << 7)
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}

/// Key values for a keyboard key
public enum KeyboardKey {
    var rawValue: UInt32 {
        switch self {
        case .backspace:
            return 0xff08
        case .tab:
            return 0xff09
        case .enter:
            return 0xff0d
        case .escape:
            return 0xff1b
        case .left:
            return 0xff51
        case .up:
            return 0xff52
        case .right:
            return 0xff53
        case .down:
            return 0xff54
        case .shiftL:
            return 0xffe1
        case .shiftR:
            return 0xffe2
        case .crtlL:
            return 0xffe3
        case .ctrlR:
            return 0xffe4
        case .altL:
            return 0xffe7
        case .altR:
            return 0xffe8
        case .metaL:
            return 0xffe9
        case .metaR:
            return 0xffea
        case .f1:
            return 0xffbe
        case .f2:
            return 0xffbf
        case .f3:
            return 0xffc0
        case .f4:
            return 0xffc1
        case .f5:
            return 0xffc2
        case .f6:
            return 0xffc3
        case .f7:
            return 0xffc4
        case .f8:
            return 0xffc5
        case .f9:
            return 0xffc6
        case .f10:
            return 0xffc7
        case .f11:
            return 0xffc8
        case .f12:
            return 0xffc9
        case .char(let character):
            print([UInt8](character.utf8), character)
            return UInt32([UInt8](character.utf8).first!)
        }
    }
    
    case backspace,
         tab,
         enter,
         escape,
         left,
         up,
         down,
         right,
         shiftL,
         shiftR,
         crtlL,
         ctrlR,
         metaL,
         metaR,
         altL,
         altR
    
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
    
    case char(Character)
}

/// The current state of the RFB connection
public enum ConnectionState: Int {
    case protocolVersion
    case authenticationType
    case authenticating
    case receivingAuthenticationResponse
    case initialisation
    case initialised
    case readingFBRectHeader
    case readingFBPixelData
    
    var isConnected: Bool { self.rawValue >= ConnectionState.initialisation.rawValue }
}

/// An error that occured while connecting to a RFB server
enum RFBError: Error {
    case alreadyConnecting
    case notConnected
    case badStream
    case invalidFrame
    case invalidAuthType
    case badAuthType
    case noAuthenticator
}

/// A class that handles a RFB connetion to a sever
public class RFBConnection: NSObject {
    /// The hostname or address of the RFB server
    public let host: String
    
    /// The port of the RFB server (default VNC port is `5900`)
    public let port: Int // = 5900
    
    /// Indicates if multiple connections should be possible simultaniously.
    public let shareFlag: Bool
    
    /// The connection delegate to notfy about connection changes
    public var delegate: RFBConnectionDelegate?
    
    public init(host: String, port: Int = 5900, shouldDisconnectOthers shareFlag: Bool = false, delegate: RFBConnectionDelegate?) {
        self.host = host
        self.port = port
        self.shareFlag = shareFlag
        self.delegate = delegate
    }
    
    /// RFB protocol version
    private static let rfbProtocol = "RFB 003.889\n"
    
    /// Current connetion state
    private(set) var connectionState: ConnectionState?
    
    /// RFB input buffer
    private var inputStream: InputStream?
    ///RFB output buffer
    private var outputStream: OutputStream?
    
    /// Selected authenticator
    private var authenticator: Authenticator?
    
    /// Buffer processor to process frame buffer updates
    private(set) var bufferProcessor: FrameBufferProcessor?
    
    /// Initializes a new connetion using the host / port parameters
    private func setupConnection() throws {
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
        
        inputStream!.schedule(in: RunLoop.current, forMode: .default)
        outputStream!.schedule(in: RunLoop.current, forMode: .default)
        
        inputStream!.open()
        outputStream!.open()
        
        inputStream!.delegate = self
        outputStream!.delegate = self
    }
    
    /// Try to connect to the RFB server if not already connected
    public func connect(on runQueue: DispatchQueue = .global(qos: .userInitiated)) throws {
        guard connectionState == nil else {
            throw RFBError.alreadyConnecting
        }
        runQueue.async {
            do {
                try self.setupConnection()
                RunLoop.current.run()
            } catch {
                self.delegate?.connectionError(reason: error.localizedDescription)
            }
        }
    }
    
    /// First RFB [Handshaking Messages](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#protocolversion)
    private func decideProtocolVersion() throws {
        guard inputStream != nil, outputStream != nil, connectionState == nil else {
            throw RFBError.badStream
        }
        
        connectionState = .protocolVersion
        
        guard let serverMsg = inputStream?.readString(maxLength: 128), !serverMsg.isEmpty else {
            throw RFBError.badStream
        }
        print("ServerProtocol:", serverMsg)
        
        outputStream?.write(string: RFBConnection.rfbProtocol)
    }
    
    /// Select RFB [security type](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#security)
    private func selectAuth() throws {
        guard inputStream != nil, outputStream != nil, connectionState == .protocolVersion else {
            throw RFBError.badStream
        }
        
        connectionState = .authenticationType
        
        guard let typesCount = inputStream?.readUInt8() else {
            throw RFBError.badStream
        }
        
        guard typesCount > 0 else {
            if let reasonLength = inputStream?.readUInt32() {
                let reason = inputStream?.readString(maxLength: Int(reasonLength))
                delegate?.connectionError(reason: reason)
            }
            return
        }
        
        guard let authenticationTypes = inputStream?.readBytes(maxLength: Int(typesCount)) else {
            throw RFBError.badStream
        }
        
        //30, 33, 36, 35, for my macOS 11
        print("AuthTypes=\(authenticationTypes)")
        
        let authTypes = AuthenticationType.factory(authenticationTypes: authenticationTypes)
        
        guard let selectedAuth = delegate?.selectAuthentication(from: authTypes),
              authTypes.contains(selectedAuth) else {
                  throw RFBError.badAuthType
              }
        
        guard selectedAuth != .invalid else { throw RFBError.invalidAuthType }
        
        guard let auther = selectedAuth.makeAuthenticator(inputStream: inputStream!, outputStream: outputStream!) else {
            throw RFBError.noAuthenticator
        }
        
        self.authenticator = auther
        print("SelectedAuth=", selectedAuth)
        outputStream?.write(bytes: [selectedAuth.value])
    }
    
    
    /// Tells the server to send a frame buffer update
    ///
    /// - See Also: [FramebufferUpdateRequest](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#framebufferupdaterequest)
    ///
    /// - Parameters:
    ///   - incremental: Update only the changed parts, don't update the entire frame
    ///   - x: X value of the area that should be updated
    ///   - y: X value of the area that should be updated
    ///   - width: Width of the area that should be updated
    ///   - height: Height of the area that should be updated
    public func requestFrameBufferUpdate(incremental: Bool, x: UInt16, y: UInt16, width: UInt16, height: UInt16) throws {
        
        guard connectionState?.isConnected == true else { throw RFBError.notConnected }
        
        guard let frameBuffer = bufferProcessor?.frameBuffer,
              x <= frameBuffer.width, y <= frameBuffer.height,
              x + width <= frameBuffer.width, y + height <= frameBuffer.height else {
                  throw RFBError.invalidFrame
              }
        
        var info = [RFBMessageTypeClient.frameBufferRequest.rawValue]
        info.append(UInt8(truncating: incremental as NSNumber))
        info.append(contentsOf: x.bytes)
        info.append(contentsOf: y.bytes)
        info.append(contentsOf: width.bytes)
        info.append(contentsOf: height.bytes)
        
        outputStream?.write(bytes: info)
    }
    
    /// Requests a frame buffer update for the entire frame
    /// - Parameter forceReload: Should reload everything or only the changed parts of the frame
    public func requestFullFrameBufferUpdate(forceReload: Bool = false) throws {
        guard let bufferProcessor = bufferProcessor, let frameBuffer = bufferProcessor.frameBuffer, connectionState?.isConnected == true else {
            throw RFBError.notConnected
        }
        
        try requestFrameBufferUpdate(incremental: !forceReload, x: 0, y: 0, width: frameBuffer.width, height: frameBuffer.height)
    }
    
    /// Sends a pointer event to the RFB server
    /// - Parameters:
    ///   - buttonMask: The buttons pressed
    ///   - location: The location of the pointer
    public func sendPointerEvert(buttonMask: PointerButtons, location: (x: UInt16, y: UInt16)) throws {
        guard connectionState?.isConnected == true else {
            throw RFBError.notConnected
        }
        
        print("Send PointerEvent: \(location); \(buttonMask)")
        var info: [UInt8] = [RFBMessageTypeClient.pointerEvent.rawValue]
        info.append(buttonMask.rawValue)
        info.append(contentsOf: location.x.bytes)
        info.append(contentsOf: location.y.bytes)
        
        outputStream?.write(bytes: info)
    }
    
    /// Send a single keyboard event
    /// - Parameters:
    ///   - key: The key concerned
    ///   - isPressedDown: Indicating if the key is pressed or released
    ///   - release: If `true` the key will be released immediately after. (default is `false`)
    public func sendKeyEvent(_ key: UInt32, isPressedDown: Bool, release: Bool = false) throws {
        var info: [UInt8] = [RFBMessageTypeClient.keyEvent.rawValue]
        info.append(isPressedDown ? 1 : 0)
        info.append(contentsOf: [0, 0])
        info.append(contentsOf: key.bytes)
        
        outputStream?.write(bytes: info)
        
        if release {
            info[1] = 0
            outputStream?.write(bytes: info)
        }
    }
    
    /// Tells the server to perform keyboard events, while holding down the keys pressed already
    /// - Parameter keys: The sequence of keys to be pressed
    public func sendKeyboardShortcuts(_ keys: [KeyboardKey]) throws {
        for key in keys {
            try sendKeyEvent(key.rawValue, isPressedDown: true)
        }
        for key in keys {
            try sendKeyEvent(key.rawValue, isPressedDown: false)
        }
    }
    
    /// Terminates the current connetion
    private func resetConnection() {
        connectionState = nil
        inputStream?.close()
        outputStream?.close()
    }
}

extension RFBConnection: StreamDelegate {
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case Stream.Event.openCompleted:
            print("OpenCompleted")
            
        case Stream.Event.errorOccurred:
            print("ErrorOccurred")
            delegate?.connectionError(reason: aStream.streamError?.localizedDescription)
            resetConnection()
            
        case Stream.Event.hasBytesAvailable:
            print("HasBytesAvailiable")
            handleBytes(from: aStream)
            
        case Stream.Event.endEncountered:
            print("Stream Endded, is input=", aStream == inputStream)
            resetConnection()
            
        default:
            break
            //            print("Unknown stream event: \(eventCode), isOut=\(aStream == outputStream)")
        }
    }
    
    /// Handles bytes recieved by the client from the server
    /// - Parameter aStream: The `inputStream` that which `hasBytesAvailable`
    private func handleBytes(from aStream: Stream) {
        guard inputStream != nil && outputStream != nil, aStream == inputStream else {
            delegate?.connectionError(reason: RFBError.badStream.localizedDescription)
            resetConnection()
            return
        }
        
        print(#function, connectionState)
        
        switch connectionState {
        case .none:
            do {
                try decideProtocolVersion()
            } catch {
                delegate?.connectionError(reason: error.localizedDescription)
                resetConnection()
            }
            
        case .protocolVersion:
            do {
                try selectAuth()
            } catch {
                delegate?.connectionError(reason: error.localizedDescription)
                resetConnection()
            }
            
        case .authenticationType:
            guard let auther = authenticator else {
                delegate?.connectionError(reason: RFBError.noAuthenticator.localizedDescription)
                resetConnection()
                return
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
            print("server msg...")
            let type = inputStream?.readUInt8()
            print("HeaderType:", type)
            
            guard let type = type, let msgType = RFBMessageTypeServer(rawValue: type) else {
                return print("Unexpected/invalid server mesage of type:", type)
            }
            
            switch msgType {
            case .framebufferUpdate:
                bufferProcessor?.readFBHeader()
                connectionState = .readingFBRectHeader
            case .setColorMap:
                break
            case .bell:
                break
            case .serverCutText:
                break
            }
            
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
