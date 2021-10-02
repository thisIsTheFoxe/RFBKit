//
//  File.swift
//  
//
//  Created by Henrik Storch on 16.06.21.
//


import Foundation
import CoreImage
import CoreGraphics


/**
 A class to proccess raw image data
 */
class ImageProcessor {
    
    /// Makes a image from a RGB32 bitmap.
    ///
    /// This means each pixel is represented by 32 bits, with 8 bits for each red, green, blue, and alpha
    /// - Parameters:
    ///   - data: Pixel data
    ///   - width: Width of the image
    ///   - height: Height of the image
    /// - Returns: The image
    static func imageFromARGB32Bitmap(data: NSData, width: Int, height: Int) -> CGImage {
        let bitsPerComponent: Int = 8
        let bitsPerPixel: Int = 32
        
        let providerRef = CGDataProvider(data: data)
        let rgb = CGColorSpaceCreateDeviceRGB()
        
        let bitmapinfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            .union(.byteOrder32Big)
        
        let cgim: CGImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: width * 4,
            space: rgb,
            bitmapInfo: bitmapinfo,
            provider: providerRef!,
            decode: nil,
            shouldInterpolate: true,
            intent: CGColorRenderingIntent.defaultIntent)!
        
        let ciInput = CIImage(cgImage: cgim)
        let ctx = CIContext(options: nil)
        let swapKernel = CIColorKernel(source:
            "kernel vec4 swapRedAndGreenAmount(__sample s) {" +
                "return s.bgra;" +
            "}"
        )
        let ciOutput = swapKernel?.apply(extent: (ciInput.extent), arguments: [ciInput as Any])
        
        return ctx.createCGImage(ciOutput!, from: (ciInput.extent))!
    }
}
