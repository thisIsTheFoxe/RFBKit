//
//  FrameBufferProcessor.swift
//  
//
//  Created by Henrik Storch on 16.06.21.
//

import Foundation
import CoreFoundation
import CoreGraphics

public protocol FrameBufferProcessorDelegate {
    func didReceive(imageUpdate: PixelRectangle)
}

public enum RFBEncoding: Int {
    case raw = 0
    
    ///RRE stands for rise-and-run-length encoding and as its name implies, it is essentially a two-dimensional analogue of run-length encoding.
    case rre = 2
}

public struct FrameBuffer {
    //frame buffer constants
    public let width: UInt16
    public let height: UInt16
    public let bitsPerPixel: UInt8
    public let depth: UInt8
    public let bigEndianFlag: UInt8
    public let trueColourFlag: UInt8
    public let redMax: UInt16
    public let greenMax: UInt16
    public let blueMax: UInt16
    public let redShift: UInt8
    public let greenShift: UInt8
    public let blueShift: UInt8
}

public class FrameBufferProcessor {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    
    private var pixelsToRead = 0
    private var rectsToRead: UInt16 = 0
    private var pixelBuffer = [UInt8]()
    
    let encodingMessageType = RFBEncoding.rre
    var pixelRectangle: PixelRectangle?
    
    public private(set) var frameBuffer: FrameBuffer?
    
    public var delegate: FrameBufferProcessorDelegate?
    
    init(inputStream: InputStream?, outputStream: OutputStream?) {
        self.inputStream = inputStream
        self.outputStream = outputStream
        
        initialise()
    }
    
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
            redMax: redMaxUInt, greenMax: greenMaxUInt, blueMax: blueMaxUInt,
            redShift: redShiftUInt, greenShift: greenShiftUInt, blueShift: blueShiftUInt)
                
        print("Frame Buffer: \(frameBuffer.debugDescription)")
        
        print("NAME=", desktopName)
    }
    
    
    func readHeader() {
        let type = inputStream?.readUInt8()
        print("HeaderType:", type)
        _ = inputStream?.readBytes(maxLength: 1)
        
        if let rectsToRead = inputStream?.readUInt16() {
            self.rectsToRead = rectsToRead
            print("rectsToRead: \(rectsToRead)")
        }
    }
    
    
    func readRectHeader() -> Bool {
        
        guard rectsToRead != 0,
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
        pixelBuffer = [UInt8](repeating: 0, count: pixelsToRead)
        
        rectsToRead -= 1
        
        return true
    }
    
    private func createImage() -> CGImage {
        return ImageProcessor.imageFromARGB32Bitmap(data: NSData(bytes: &pixelBuffer, length: pixelBuffer.count), width: pixelRectangle!.width, height: pixelRectangle!.height)
    }
    
    
    //transfer pixels directly to buffer, then we'll update the image
    private func addPixelsToBuffer(buffer: [UInt8], len: Int) {
        
        //need to use pixelsToRead and the size and x/y position of the rectangle we're trying to draw to do this
        //every rect width need to go down a level
        //figure out coordinates in pixel rect
        //then transfer this to overall thing?
        let pixelsRead = pixelRectangle!.width * pixelRectangle!.height * 4 - pixelsToRead
        let xCoordInRect = pixelsRead % (pixelRectangle!.width * 4)
        let yCoordInRect = pixelsRead / (pixelRectangle!.width * 4)
        
        var initialIndex = pixelRectangle!.yvalue + yCoordInRect
        initialIndex *= pixelRectangle!.width * 4
        initialIndex += pixelRectangle!.xvalue  * 4
        initialIndex += xCoordInRect
        //print("Initial index: \(initialIndex)")
        //outer for loop goes through every level
        
        for i in 0..<len {
            var curIndex = ((pixelsRead + i) / (pixelRectangle!.width * 4)) - yCoordInRect
            curIndex *= pixelRectangle!.width * 4 - pixelRectangle!.width * 4
            curIndex += initialIndex + i
            pixelBuffer[curIndex] = buffer[i]
        }
    }
    
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

///Sent from client -> Server
enum RFBMessageTypeClient: UInt8 {
    case setPixelFormat = 0
    case setEncodings = 2
    case frameBufferRequest = 3
    case keyEvent = 4
    case pointerEvent = 5
    case clientCutText = 6
}

///Received by Client from Server
enum RFBMessageTypeServer: UInt8 {
    case framebufferUpdate = 0
    case setColorMap = 1
    case bell = 2
    case serverCutText = 3
}


enum FrameBufferStatus {
    case keepReadingPixels, readNextRect, done
}
