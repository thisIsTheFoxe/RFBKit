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

public class FrameBufferProcessor {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    
    let encodingMessageType = RFBEncoding.rre
    var pixelRectangle: PixelRectangle?
    
    var pixelsToRead = 0
    var rectsToRead: UInt16 = 0
    var pixelBuffer = [UInt8]()
    
    public var delegate: FrameBufferProcessorDelegate?
    
    struct Point {
        var x = 0
        var y = 0
    }
   // var rects = [Point:(Int, Int)]()
    
    init(inputStream: InputStream?, outputStream: OutputStream?) {
        self.inputStream = inputStream
        self.outputStream = outputStream
        
        initialise()
    }
    
    //frame buffer constants
    public private(set) var framebufferwidth: UInt16 = 0
    public private(set) var framebufferheight: UInt16 = 0
    public private(set) var bitsperpixel: UInt8 = 0
    public private(set) var depth: UInt8 = 0
    public private(set) var bigendianflag: UInt8 = 0
    public private(set) var truecolourflag: UInt8 = 0
    public private(set) var redmax: UInt16 = 0
    public private(set) var greenmax: UInt16 = 0
    public private(set) var bluemax: UInt16 = 0
    public private(set) var redshift: UInt8 = 0
    public private(set) var greenshift: UInt8 = 0
    public private(set) var blueshift: UInt8 = 0
    
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
        
        //extract constants
        framebufferwidth = fBWidthUInt
        framebufferheight = fBHeightUint
        bitsperpixel = bitPerPixelUInt
        depth = depthUInt
        bigendianflag = bigEndianFlagUInt
        truecolourflag = trueColourFlagUInt
        redmax = redMaxUInt
        greenmax = greenMaxUInt
        bluemax = blueMaxUInt
        redshift = redShiftUInt
        greenshift = greenShiftUInt
        blueshift = blueShiftUInt
        
        print("Frame Width: \(framebufferwidth)")
        print("Frame Height: \(framebufferheight)")
        print("Bits Per Pixel: \(bitsperpixel)")
        print("True colour: \(truecolourflag)")
        print("Depth:  \(depth)")
        print("redmax:  \(redmax)")
        print("redshift:  \(redshift)")
        
        print("NAME=", desktopName)
    }
    
    //return the number of pixels found
    private func ingestRectangle(offset: Int, data: NSData) -> PixelRectangle {
        var xvalue = 0
        var yvalue = 0
        var width = 0
        var height = 0
        var encodingtype = 0
        data.getBytes(&xvalue, range: NSMakeRange(offset, 2))
        data.getBytes(&yvalue, range: NSMakeRange(offset + 2, 2))
        data.getBytes(&width, range: NSMakeRange(offset + 4, 2))
        data.getBytes(&height, range: NSMakeRange(offset + 6, 2))
        data.getBytes(&encodingtype, range: NSMakeRange(offset + 8, 4))
        xvalue = Int(CFSwapInt16(UInt16(xvalue)))
        yvalue = Int(CFSwapInt16(UInt16(yvalue)))
        width = Int(CFSwapInt16(UInt16(width)))
        height = Int(CFSwapInt16(UInt16(height)))
        encodingtype = Int(CFSwapInt16(UInt16(encodingtype)))
        
        print("xvalue: \(xvalue)")
        print("yvalue: \(yvalue)")
        print("width: \(width)")
        print("height: \(height)")
        print("encodingtype: \(encodingtype)")
        return PixelRectangle(xvalue: xvalue, yvalue: yvalue, width: width, height: height, encodingtype: encodingtype, image: nil)
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
        
        guard rectsToRead != 0, let data = inputStream?.readData(maxLength: 12) else {
            return false
        }
        
        pixelRectangle = ingestRectangle(offset: 0, data: data as NSData)
        rectsToRead -= 1
        pixelsToRead = pixelRectangle!.width * pixelRectangle!.height * 4
        return true
    }
    
    private func createImage() -> CGImage {
#warning("Always uses framebufferwidth instead of dynamic (requested) size")
        return ImageProcessor.imageFromARGB32Bitmap(data: NSData(bytes: &pixelBuffer, length: pixelBuffer.count), width: Int(framebufferwidth), height: Int(framebufferheight))
    }
    
    
    //transfer pixels directly to buffer, then we'll update the image
    private func addPixelsToBuffer(buffer: [UInt8], len: Int) {
#warning("Always uses framebufferwidth instead of dynamic (requested) size")
        
        //need to use pixelsToRead and the size and x/y position of the rectangle we're trying to draw to do this
        //every rect width need to go down a level
        //figure out coordinates in pixel rect
        //then transfer this to overall thing?
        let pixelsRead = pixelRectangle!.width * pixelRectangle!.height * 4 - pixelsToRead
        let xCoordInRect = pixelsRead % (pixelRectangle!.width * 4)
        let yCoordInRect = pixelsRead / (pixelRectangle!.width * 4)
        
        let initialIndex = ((pixelRectangle!.yvalue) + yCoordInRect) * (Int(framebufferwidth) * 4) + (pixelRectangle!.xvalue  * 4) + xCoordInRect
        //print("Initial index: \(initialIndex)")
        //outer for loop goes through every level
        
        for i in 0..<len {
            let curIndex = (initialIndex + i) + (Int(framebufferwidth) * 4 - pixelRectangle!.width * 4) * (((pixelsRead + i) / (pixelRectangle!.width * 4)) - yCoordInRect)
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
