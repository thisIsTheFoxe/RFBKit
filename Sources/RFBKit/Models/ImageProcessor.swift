//
//  File.swift
//  
//
//  Created by Henrik Storch on 16.06.21.
//


import Foundation
import CoreImage
import CoreGraphics

class ImageProcessor {
    static func imageFromARGB32Bitmap(data: NSData, width:Int, height:Int) -> CGImage {
        let bitsPerComponent:Int = 8
        let bitsPerPixel:Int = 32
        
        let providerRef = CGDataProvider(data: data)
        let rgb = CGColorSpaceCreateDeviceRGB()
        
        let bitmapinfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            .union(.byteOrder32Big)
        
        let cgim: CGImage = CGImage(width: width, height: height, bitsPerComponent: bitsPerComponent, bitsPerPixel: bitsPerPixel, bytesPerRow: width * 4, space: rgb, bitmapInfo: bitmapinfo, provider: providerRef!, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent)!
        
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
