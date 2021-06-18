//
//  PixelRectangle.swift
//  
//
//  Created by Henrik Storch on 16.06.21.
//

import Foundation
import CoreGraphics

public class PixelRectangle {
    public var xvalue = 0
    public var yvalue = 0
    public var width = 0
    public var height = 0
    public var encodingtype = 0
    public var image: CGImage?
    
    init(xvalue: Int, yvalue: Int, width: Int, height: Int, encodingtype: Int, image: CGImage?) {
        self.xvalue = xvalue
        self.yvalue = yvalue
        self.width = width
        self.height = height
        self.encodingtype = encodingtype
        self.image = image
    }
}
