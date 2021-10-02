//
//  FrameBufferProcessor.swift
//  
//
//  Created by Henrik Storch on 16.06.21.
//

import Foundation
import CoreFoundation
import CoreGraphics

/// A delegate to be notified about updates of a frame buffer
public protocol FrameBufferProcessorDelegate {
    func didReceive(imageUpdate: PixelRectangle)
}

/// The framebuffer encoding
public enum RFBEncoding: Int {
    case raw = 0
    
    ///RRE stands for rise-and-run-length encoding and as its name implies, it is essentially a two-dimensional analogue of run-length encoding.
    case rre = 2
}

/// A struct holding information about a frame buffer
public struct FrameBuffer {
    //frame buffer constants
    public let width: UInt16
    public let height: UInt16
    public let bitsPerPixel: UInt8
    public let depth: UInt8
    public let bigEndianFlag: UInt8
    public let trueColourFlag: UInt8
    public let maxColorValue: (red: UInt16, green: UInt16, blue: UInt16)
    public let colorShift: (red: UInt8, green: UInt8, blue: UInt8)
    public let name: String
}

/// A class that handles frame buffer messages
public class FrameBufferProcessor {
    /// RFB input stream
    private var inputStream: InputStream?
    /// RFB output stream
    private var outputStream: OutputStream?
    
    /// Pixels left to read for the frame buffer to be filled
    private var pixelsToRead = 0
    
    /// Number of pixels rectangles are left to be read
    private var rectsToRead: UInt16 = 0
    
    /// The total buffer of all pixels of the image
    private var pixelBuffer = [UInt8]()
    
    /// RFB encodig type
    let encodingMessageType = RFBEncoding.rre
    
    /// The current pixel rectable being worked at
    var pixelRectangle: PixelRectangle?
    
    /// The metadata about the current frame buffer
    public private(set) var frameBuffer: FrameBuffer?
    
    /// The delegte to notify others about changes
    public var delegate: FrameBufferProcessorDelegate?
    
    init(inputStream: InputStream?, outputStream: OutputStream?) {
        self.inputStream = inputStream
        self.outputStream = outputStream
        
        initialise()
    }
    
    /// Reads the [ServerInit](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#serverinit) message of a RFB connection
    func initialise() {
        guard let inputStream = inputStream else {
            return
        }
        
        guard let fBWidthUInt = inputStream.readUInt16(),
              let fBHeightUint = inputStream.readUInt16(),
              let bitPerPixelUInt = inputStream.readUInt8(),
              let depthUInt = inputStream.readUInt8(),
              let bigEndianFlagUInt = inputStream.readUInt8(),
              let trueColourFlagUInt = inputStream.readUInt8(),
              let redMaxUInt = inputStream.readUInt16(),
              let greenMaxUInt = inputStream.readUInt16(),
              let blueMaxUInt = inputStream.readUInt16(),
              let redShiftUInt = inputStream.readUInt8(),
              let greenShiftUInt = inputStream.readUInt8(),
              let blueShiftUInt = inputStream.readUInt8(),
              inputStream.readBytes(maxLength: 3) != nil,
              let nameLength = inputStream.readUInt32(),
              let desktopName = inputStream.readString(maxLength: Int(nameLength))
        else {
            return
        }
        
        frameBuffer = FrameBuffer(
            width: fBWidthUInt,
            height: fBHeightUint,
            bitsPerPixel: bitPerPixelUInt,
            depth: depthUInt,
            bigEndianFlag: bigEndianFlagUInt,
            trueColourFlag: trueColourFlagUInt,
            maxColorValue: (red: redMaxUInt, green: greenMaxUInt, blue: blueMaxUInt),
            colorShift: (red: redShiftUInt, green: greenShiftUInt, blue: blueShiftUInt),
            name: desktopName)
        
        pixelBuffer = [UInt8](repeating: 0, count: Int(frameBuffer!.width) * Int(frameBuffer!.height) * 4)
        
        print("Frame Buffer: \(frameBuffer.debugDescription)")
        
        print("NAME=", desktopName)
    }
    
    
    /// Reads the header of a frame buffer update message
    func readFBHeader() {
//        let type = inputStream?.readUInt8()
//        print("HeaderType:", type)
        
        //padding
        _ = inputStream?.readBytes(maxLength: 1)
        
        if let rectsToRead = inputStream?.readUInt16() {
            self.rectsToRead = rectsToRead
            print("rectsToRead: \(rectsToRead)")
        }
    }
    
    /// Reads the header of a pixel rectangle
    /// - Returns: `false` if there are still rects left to read
    func readRectHeader() -> Bool {
        guard rectsToRead > 0,
              let xvalue = inputStream?.readUInt16(),
              let yvalue = inputStream?.readUInt16(),
              let width = inputStream?.readUInt16(),
              let height = inputStream?.readUInt16(),
              let encodingtype = inputStream?.readInt32()
        else {
            return false
        }
        
        pixelRectangle = PixelRectangle(xvalue: Int(xvalue), yvalue: Int(yvalue), width: Int(width), height: Int(height), encodingtype: Int(encodingtype), image: nil)
        pixelsToRead = pixelRectangle!.width * pixelRectangle!.height * 4
        
        rectsToRead -= 1
        
        return true
    }
    
    /// Makes a `CGImage` from the current frame buffer
    private func createImage() -> CGImage {
        return ImageProcessor.imageFromARGB32Bitmap(data: NSData(bytes: &pixelBuffer, length: pixelBuffer.count), width: Int(frameBuffer!.width), height: Int(frameBuffer!.height))
    }
    
    /// Transfers pixels directly to buffer and updates the image
    private func addPixelsToBuffer(buffer: [UInt8], len: Int) {
        //need to use pixelsToRead and the size and x/y position of the rectangle we're trying to draw to do this
        //every rect width need to go down a level
        //figure out coordinates in pixel rect
        //then transfer this to overall thing?
        let pixelsRead = pixelRectangle!.width * pixelRectangle!.height * 4 - pixelsToRead
        let xCoordInRect = pixelsRead % (pixelRectangle!.width * 4)
        let yCoordInRect = pixelsRead / (pixelRectangle!.width * 4)
        
        var initialIndex = yCoordInRect + pixelRectangle!.yvalue
        initialIndex *= Int(frameBuffer!.width) * 4
        initialIndex += pixelRectangle!.xvalue * 4
        initialIndex += xCoordInRect
        //print("Initial index: \(initialIndex)")
        //outer for loop goes through every level
        
        let widthDifference = Int(frameBuffer!.width) * 4 - pixelRectangle!.width * 4
        
        for i in 0..<len {
            var curIndex = ((pixelsRead + i) / (pixelRectangle!.width * 4)) - yCoordInRect
            curIndex *= widthDifference
            curIndex += initialIndex + i
            pixelBuffer[curIndex] = buffer[i]
        }
    }
    
    /// Reads pixel data from the `inputStream`
    /// - Returns: The `FrameBufferStatus`, e.g. if more pixels need to be read
    func getPixelData() -> FrameBufferStatus {
        if pixelsToRead > 0 {
           
            var buffer = [UInt8](repeating: 0, count: pixelsToRead)
            let len = inputStream!.read(&buffer, maxLength: buffer.count)
            
            addPixelsToBuffer(buffer: buffer, len: len)
            pixelsToRead -= len
            print("Len: \(len)")
            print("pixels left: \(pixelsToRead)")
        }
        if pixelsToRead == 0 {
            print("rectsToRead: \(rectsToRead)")
            let image = createImage()
            pixelRectangle!.image = image
            
            delegate?.didReceive(imageUpdate: pixelRectangle!)
            
            if rectsToRead > 0 {
                return .readNextRect
            }
            else { return .done }
        }
        return .keepReadingPixels
    }
}

/// Message sent from client to server
enum RFBMessageTypeClient: UInt8 {
    case setPixelFormat = 0
    case setEncodings = 2
    case frameBufferRequest = 3
    case keyEvent = 4
    case pointerEvent = 5
    case clientCutText = 6
}

///Message received by client from server
enum RFBMessageTypeServer: UInt8 {
    case framebufferUpdate = 0
    case setColorMap = 1
    case bell = 2
    case serverCutText = 3
}

/// Status of the frame buffer
enum FrameBufferStatus {
    case keepReadingPixels, readNextRect, done
}
