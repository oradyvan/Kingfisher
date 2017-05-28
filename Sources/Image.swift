//
//  Image.swift
//  Kingfisher
//
//  Created by Wei Wang on 16/1/6.
//
//  Copyright (c) 2017 Wei Wang <onevcat@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.


#if os(macOS)
import AppKit
private var imagesKey: Void?
private var durationKey: Void?
#else
import UIKit
import MobileCoreServices
private var imageSourceKey: Void?
#endif
private var animatedImageDataKey: Void?

import ImageIO
import CoreGraphics

#if !os(watchOS)
import Accelerate
import CoreImage
#endif

// MARK: - Image Properties
extension Kingfisher where Base: Image {
    fileprivate(set) var animatedImageData: Data? {
        get {
            return objc_getAssociatedObject(base, &animatedImageDataKey) as? Data
        }
        set {
            objc_setAssociatedObject(base, &animatedImageDataKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    #if os(macOS)
    var cgImage: CGImage? {
        return base.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    var scale: CGFloat {
        return 1.0
    }
    
    fileprivate(set) var images: [Image]? {
        get {
            return objc_getAssociatedObject(base, &imagesKey) as? [Image]
        }
        set {
            objc_setAssociatedObject(base, &imagesKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    fileprivate(set) var duration: TimeInterval {
        get {
            return objc_getAssociatedObject(base, &durationKey) as? TimeInterval ?? 0.0
        }
        set {
            objc_setAssociatedObject(base, &durationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var size: CGSize {
        return base.representations.reduce(CGSize.zero, { size, rep in
            return CGSize(width: max(size.width, CGFloat(rep.pixelsWide)), height: max(size.height, CGFloat(rep.pixelsHigh)))
        })
    }
    
    #else
    var cgImage: CGImage? {
        return base.cgImage
    }
    
    var scale: CGFloat {
        return base.scale
    }
    
    var images: [Image]? {
        return base.images
    }
    
    var duration: TimeInterval {
        return base.duration
    }
    
    fileprivate(set) var imageSource: ImageSource? {
        get {
            return objc_getAssociatedObject(base, &imageSourceKey) as? ImageSource
        }
        set {
            objc_setAssociatedObject(base, &imageSourceKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    var size: CGSize {
        return base.size
    }
    #endif
}

// MARK: - Image Conversion
extension Kingfisher where Base: Image {
    #if os(macOS)
    static func image(cgImage: CGImage, scale: CGFloat, refImage: Image?) -> Image {
        return Image(cgImage: cgImage, size: CGSize.zero)
    }
    
    /**
     Normalize the image. This method does nothing in OS X.
     
     - returns: The image itself.
     */
    public var normalized: Image {
        return base
    }
    
    static func animated(with images: [Image], forDuration forDurationduration: TimeInterval) -> Image? {
        return nil
    }
    #else
    static func image(cgImage: CGImage, scale: CGFloat, refImage: Image?) -> Image {
        if let refImage = refImage {
            return Image(cgImage: cgImage, scale: scale, orientation: refImage.imageOrientation)
        } else {
            return Image(cgImage: cgImage, scale: scale, orientation: .up)
        }
    }
    
    /**
     Normalize the image. This method will try to redraw an image with orientation and scale considered.
     
     - returns: The normalized image with orientation set to up and correct scale.
     */
    public var normalized: Image {
        // prevent animated image (GIF) lose it's images
        guard images == nil else { return base }
        // No need to do anything if already up
        guard base.imageOrientation != .up else { return base }
    
        return draw(cgImage: nil, to: size) {
            base.draw(in: CGRect(origin: CGPoint.zero, size: size))
        }
    }
    
    static func animated(with images: [Image], forDuration duration: TimeInterval) -> Image? {
        return .animatedImage(with: images, duration: duration)
    }
    #endif
}

// MARK: - Image Representation
extension Kingfisher where Base: Image {
    // MARK: - PNG
    public func pngRepresentation() -> Data? {
        #if os(macOS)
            guard let cgimage = cgImage else {
                return nil
            }
            let rep = NSBitmapImageRep(cgImage: cgimage)
            return rep.representation(using: .PNG, properties: [:])
        #else
            return UIImagePNGRepresentation(base)
        #endif
    }
    
    // MARK: - JPEG
    public func jpegRepresentation(compressionQuality: CGFloat) -> Data? {
        #if os(macOS)
            guard let cgImage = cgImage else {
                return nil
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            return rep.representation(using:.JPEG, properties: [NSImageCompressionFactor: compressionQuality])
        #else
            return UIImageJPEGRepresentation(base, compressionQuality)
        #endif
    }
    
    // MARK: - GIF
    public func gifRepresentation() -> Data? {
        return animatedImageData
    }
}

// MARK: - Create images from data
extension Kingfisher where Base: Image {
    static func animated(with data: Data, scale: CGFloat = 1.0, duration: TimeInterval = 0.0, preloadAll: Bool, onlyFirstFrame: Bool = false) -> Image? {
        
        func decode(from imageSource: CGImageSource, for options: NSDictionary) -> ([Image], TimeInterval)? {
            
            //Calculates frame duration for a gif frame out of the kCGImagePropertyGIFDictionary dictionary
            func frameDuration(from gifInfo: NSDictionary?) -> Double {
                let gifDefaultFrameDuration = 0.100
                
                guard let gifInfo = gifInfo else {
                    return gifDefaultFrameDuration
                }
                
                let unclampedDelayTime = gifInfo[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber
                let delayTime = gifInfo[kCGImagePropertyGIFDelayTime as String] as? NSNumber
                let duration = unclampedDelayTime ?? delayTime
                
                guard let frameDuration = duration else { return gifDefaultFrameDuration }
                
                return frameDuration.doubleValue > 0.011 ? frameDuration.doubleValue : gifDefaultFrameDuration
            }
            
            let frameCount = CGImageSourceGetCount(imageSource)
            var images = [Image]()
            var gifDuration = 0.0
            for i in 0 ..< frameCount {
                
                guard let imageRef = CGImageSourceCreateImageAtIndex(imageSource, i, options) else {
                    return nil
                }

                if frameCount == 1 {
                    // Single frame
                    gifDuration = Double.infinity
                } else {
                    
                    // Animated GIF
                    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil) else {
                        return nil
                    }

                    let gifInfo = (properties as NSDictionary)[kCGImagePropertyGIFDictionary as String] as? NSDictionary
                    gifDuration += frameDuration(from: gifInfo)
                }
                
                images.append(Kingfisher<Image>.image(cgImage: imageRef, scale: scale, refImage: nil))
                
                if onlyFirstFrame { break }
            }
            
            return (images, gifDuration)
        }
        
        // Start of kf.animatedImageWithGIFData
        let options: NSDictionary = [kCGImageSourceShouldCache as String: true, kCGImageSourceTypeIdentifierHint as String: kUTTypeGIF]
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }
        
        #if os(macOS)
            guard let (images, gifDuration) = decode(from: imageSource, for: options) else {
                return nil
            }
            let image: Image?
            if onlyFirstFrame {
                image = images.first
            } else {
                image = Image(data: data)
                image?.kf.images = images
                image?.kf.duration = gifDuration
            }
            image?.kf.animatedImageData = data
            return image
        #else
            
            let image: Image?
            if preloadAll || onlyFirstFrame {
                guard let (images, gifDuration) = decode(from: imageSource, for: options) else { return nil }
                image = onlyFirstFrame ? images.first : Kingfisher<Image>.animated(with: images, forDuration: duration <= 0.0 ? gifDuration : duration)
            } else {
                image = Image(data: data)
                image?.kf.imageSource = ImageSource(ref: imageSource)
            }
            image?.kf.animatedImageData = data
            return image
        #endif
    }

    static func image(data: Data, scale: CGFloat, preloadAllAnimationData: Bool, onlyFirstFrame: Bool) -> Image? {
        var image: Image?

        #if os(macOS)
            switch data.kf.imageFormat {
            case .JPEG:
                image = Image(data: data)
            case .PNG:
                image = Image(data: data)
            case .GIF:
                image = Kingfisher<Image>.animated(
                    with: data,
                    scale: scale,
                    duration: 0.0,
                    preloadAll: preloadAllAnimationData,
                    onlyFirstFrame: onlyFirstFrame)
            case .unknown:
                image = Image(data: data)
            }
        #else
            switch data.kf.imageFormat {
            case .JPEG:
                image = Image(data: data, scale: scale)
            case .PNG:
                image = Image(data: data, scale: scale)
            case .GIF:
                image = Kingfisher<Image>.animated(
                    with: data,
                    scale: scale,
                    duration: 0.0,
                    preloadAll: preloadAllAnimationData,
                    onlyFirstFrame: onlyFirstFrame)
            case .unknown:
                image = Image(data: data, scale: scale)
            }
        #endif

        return image
    }
}

// MARK: - Image Transforming
extension Kingfisher where Base: Image {

    // MARK: - Round Corner
    /// Create a round corner image based on `self`.
    ///
    /// - parameter radius:  The round corner radius of creating image.
    /// - parameter size:    The target size of creating image.
    /// - parameter corners: The target corners which will be applied rounding.
    ///
    /// - returns: An image with round corner of `self`.
    ///
    /// - Note: This method only works for CG-based image.
    public func image(withRoundRadius radius: CGFloat,
                      fit size: CGSize,
                      roundingCorners corners: RectCorner = .all) -> Image
    {   
        guard let cgImage = cgImage else {
            assertionFailure("[Kingfisher] Round corner image only works for CG-based image.")
            return base
        }
        
        let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: size)
        return draw(cgImage: cgImage, to: size) {
            #if os(macOS)
                let path = NSBezierPath(roundedRect: rect, byRoundingCorners: corners, radius: radius)
                path.windingRule = .evenOddWindingRule
                path.addClip()
                base.draw(in: rect)
            #else
                guard let context = UIGraphicsGetCurrentContext() else {
                    assertionFailure("[Kingfisher] Failed to create CG context for image.")
                    return
                }
                let path = UIBezierPath(roundedRect: rect,
                                        byRoundingCorners: corners.uiRectCorner,
                                        cornerRadii: CGSize(width: radius, height: radius)).cgPath
                context.addPath(path)
                context.clip()
                base.draw(in: rect)
            #endif
        }
    }
    
    #if os(iOS) || os(tvOS)
    func resize(to size: CGSize, for contentMode: UIViewContentMode) -> Image {
        switch contentMode {
        case .scaleAspectFit:
            return resize(to: size, for: .aspectFit)
        case .scaleAspectFill:
            return resize(to: size, for: .aspectFill)
        default:
            return resize(to: size)
        }
    }
    #endif
    
    // MARK: - Resize
    /// Resize `self` to an image of new size.
    ///
    /// - parameter size: The target size.
    ///
    /// - returns: An image with new size.
    ///
    /// - Note: This method only works for CG-based image.
    public func resize(to size: CGSize) -> Image {
        
        guard let cgImage = cgImage else {
            assertionFailure("[Kingfisher] Resize only works for CG-based image.")
            return base
        }
        
        let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: size)
        return draw(cgImage: cgImage, to: size) {
            #if os(macOS)
                base.draw(in: rect, from: NSRect.zero, operation: .copy, fraction: 1.0)
            #else
                base.draw(in: rect)
            #endif
        }
    }
    
    /// Resize `self` to an image of new size, respecting the content mode.
    ///
    /// - Parameters:
    ///   - size: The target size.
    ///   - contentMode: Content mode of output image should be.
    /// - Returns: An image with new size.
    public func resize(to size: CGSize, for contentMode: ContentMode) -> Image {
        switch contentMode {
        case .aspectFit:
            let newSize = self.size.kf.constrained(size)
            return resize(to: newSize)
        case .aspectFill:
            let newSize = self.size.kf.filling(size)
            return resize(to: newSize)
        default:
            return resize(to: size)
        }
    }
    
    public func crop(to size: CGSize, anchorOn anchor: CGPoint) -> Image {
        guard let cgImage = cgImage else {
            assertionFailure("[Kingfisher] Crop only works for CG-based image.")
            return base
        }
        
        let rect = self.size.kf.constrainedRect(for: size, anchor: anchor)
        guard let image = cgImage.cropping(to: rect.scaled(scale)) else {
            assertionFailure("[Kingfisher] Cropping image failed.")
            return base
        }
        
        return Kingfisher.image(cgImage: image, scale: scale, refImage: base)
    }
    
    // MARK: - Blur
    
    /// Create an image with blur effect based on `self`.
    ///
    /// - parameter radius: The blur radius should be used when creating blue.
    ///
    /// - returns: An image with blur effect applied.
    ///
    /// - Note: This method only works for CG-based image.
    public func blurred(withRadius radius: CGFloat) -> Image {
        #if os(watchOS)
            return base
        #else
            guard let cgImage = cgImage else {
                assertionFailure("[Kingfisher] Blur only works for CG-based image.")
                return base
            }
            
            // http://www.w3.org/TR/SVG/filters.html#feGaussianBlurElement
            // let d = floor(s * 3*sqrt(2*pi)/4 + 0.5)
            // if d is odd, use three box-blurs of size 'd', centered on the output pixel.
            let s = Float(max(radius, 2.0))
            // We will do blur on a resized image (*0.5), so the blur radius could be half as well.
            
            // Fix the slow compiling time for Swift 3. 
            // See https://github.com/onevcat/Kingfisher/issues/611
            let pi2 = 2 * Float.pi
            let sqrtPi2 = sqrt(pi2)
            var targetRadius = floor(s * 3.0 * sqrtPi2 / 4.0 + 0.5)
            
            if targetRadius.isEven {
                targetRadius += 1
            }
            
            let iterations: Int
            if radius < 0.5 {
                iterations = 1
            } else if radius < 1.5 {
                iterations = 2
            } else {
                iterations = 3
            }
            
            let w = Int(size.width)
            let h = Int(size.height)
            let rowBytes = Int(CGFloat(cgImage.bytesPerRow))
            
            func createEffectBuffer(_ context: CGContext) -> vImage_Buffer {
                let data = context.data
                let width = vImagePixelCount(context.width)
                let height = vImagePixelCount(context.height)
                let rowBytes = context.bytesPerRow
                
                return vImage_Buffer(data: data, height: height, width: width, rowBytes: rowBytes)
            }

            guard let context = beginContext(size: size) else {
                assertionFailure("[Kingfisher] Failed to create CG context for blurring image.")
                return base
            }
            defer { endContext() }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            
            var inBuffer = createEffectBuffer(context)
            
            guard let outContext = beginContext(size: size) else {
                assertionFailure("[Kingfisher] Failed to create CG context for blurring image.")
                return base
            }
            defer { endContext() }
            var outBuffer = createEffectBuffer(outContext)
            
            for _ in 0 ..< iterations {
                vImageBoxConvolve_ARGB8888(&inBuffer, &outBuffer, nil, 0, 0, UInt32(targetRadius), UInt32(targetRadius), nil, vImage_Flags(kvImageEdgeExtend))
                (inBuffer, outBuffer) = (outBuffer, inBuffer)
            }
            
            #if os(macOS)
                let result = outContext.makeImage().flatMap { fixedForRetinaPixel(cgImage: $0, to: size) }
            #else
                let result = outContext.makeImage().flatMap { Image(cgImage: $0, scale: base.scale, orientation: base.imageOrientation) }
            #endif
            guard let blurredImage = result else {
                assertionFailure("[Kingfisher] Can not make an blurred image within this context.")
                return base
            }
            
            return blurredImage
        #endif
    }
    
    // MARK: - Overlay
    
    /// Create an image from `self` with a color overlay layer.
    ///
    /// - parameter color:    The color should be use to overlay.
    /// - parameter fraction: Fraction of input color. From 0.0 to 1.0. 0.0 means solid color, 1.0 means transparent overlay.
    ///
    /// - returns: An image with a color overlay applied.
    ///
    /// - Note: This method only works for CG-based image.
    public func overlaying(with color: Color, fraction: CGFloat) -> Image {
        
        guard let cgImage = cgImage else {
            assertionFailure("[Kingfisher] Overlaying only works for CG-based image.")
            return base
        }
        
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        return draw(cgImage: cgImage, to: rect.size) {
            #if os(macOS)
                base.draw(in: rect)
                if fraction > 0 {
                    color.withAlphaComponent(1 - fraction).set()
                    NSRectFillUsingOperation(rect, .sourceAtop)
                }
            #else
                color.set()
                UIRectFill(rect)
                base.draw(in: rect, blendMode: .destinationIn, alpha: 1.0)
                
                if fraction > 0 {
                    base.draw(in: rect, blendMode: .sourceAtop, alpha: fraction)
                }
            #endif
        }
    }
    
    // MARK: - Tint
    
    /// Create an image from `self` with a color tint.
    ///
    /// - parameter color: The color should be used to tint `self`
    ///
    /// - returns: An image with a color tint applied.
    public func tinted(with color: Color) -> Image {
        #if os(watchOS)
            return base
        #else
            return apply(.tint(color))
        #endif
    }
    
    // MARK: - Color Control
    
    /// Create an image from `self` with color control.
    ///
    /// - parameter brightness: Brightness changing to image.
    /// - parameter contrast:   Contrast changing to image.
    /// - parameter saturation: Saturation changing to image.
    /// - parameter inputEV:    InputEV changing to image.
    ///
    /// - returns: An image with color control applied.
    public func adjusted(brightness: CGFloat, contrast: CGFloat, saturation: CGFloat, inputEV: CGFloat) -> Image {
        #if os(watchOS)
            return base
        #else
            return apply(.colorControl(brightness, contrast, saturation, inputEV))
        #endif
    }
}

// MARK: - Decode
extension Kingfisher where Base: Image {
    var decoded: Image? {
        return decoded(scale: scale)
    }
    
    func decoded(scale: CGFloat) -> Image {
        // prevent animated image (GIF) lose it's images
        #if os(iOS)
            if imageSource != nil { return base }
        #else
            if images != nil { return base }
        #endif
        
        guard let imageRef = self.cgImage else {
            assertionFailure("[Kingfisher] Decoding only works for CG-based image.")
            return base
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = beginContext(size: CGSize(width: imageRef.width, height: imageRef.height)) else {
            assertionFailure("[Kingfisher] Decoding fails to create a valid context.")
            return base
        }
        
        defer { endContext() }
        
        let rect = CGRect(x: 0, y: 0, width: imageRef.width, height: imageRef.height)
        context.draw(imageRef, in: rect)
        let decompressedImageRef = context.makeImage()
        return Kingfisher<Image>.image(cgImage: decompressedImageRef!, scale: scale, refImage: base)
    }
}

/// Reference the source image reference
class ImageSource {
    var imageRef: CGImageSource?
    init(ref: CGImageSource) {
        self.imageRef = ref
    }
}

// MARK: - Image format
private struct ImageHeaderData {
    static var PNG: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    static var JPEG_SOI: [UInt8] = [0xFF, 0xD8]
    static var JPEG_IF: [UInt8] = [0xFF]
    static var GIF: [UInt8] = [0x47, 0x49, 0x46]
}

enum ImageFormat {
    case unknown, PNG, JPEG, GIF
}


// MARK: - Misc Helpers
public struct DataProxy {
    fileprivate let base: Data
    init(proxy: Data) {
        base = proxy
    }
}

extension Data: KingfisherCompatible {
    public typealias CompatibleType = DataProxy
    public var kf: DataProxy {
        return DataProxy(proxy: self)
    }
}

extension DataProxy {
    var imageFormat: ImageFormat {
        var buffer = [UInt8](repeating: 0, count: 8)
        (base as NSData).getBytes(&buffer, length: 8)
        if buffer == ImageHeaderData.PNG {
            return .PNG
        } else if buffer[0] == ImageHeaderData.JPEG_SOI[0] &&
            buffer[1] == ImageHeaderData.JPEG_SOI[1] &&
            buffer[2] == ImageHeaderData.JPEG_IF[0]
        {
            return .JPEG
        } else if buffer[0] == ImageHeaderData.GIF[0] &&
            buffer[1] == ImageHeaderData.GIF[1] &&
            buffer[2] == ImageHeaderData.GIF[2]
        {
            return .GIF
        }

        return .unknown
    }
}

public struct CGSizeProxy {
    fileprivate let base: CGSize
    init(proxy: CGSize) {
        base = proxy
    }
}

extension CGSize: KingfisherCompatible {
    public typealias CompatibleType = CGSizeProxy
    public var kf: CGSizeProxy {
        return CGSizeProxy(proxy: self)
    }
}

extension CGSizeProxy {
    func constrained(_ size: CGSize) -> CGSize {
        let aspectWidth = round(aspectRatio * size.height)
        let aspectHeight = round(size.width / aspectRatio)

        return aspectWidth > size.width ? CGSize(width: size.width, height: aspectHeight) : CGSize(width: aspectWidth, height: size.height)
    }

    func filling(_ size: CGSize) -> CGSize {
        let aspectWidth = round(aspectRatio * size.height)
        let aspectHeight = round(size.width / aspectRatio)

        return aspectWidth < size.width ? CGSize(width: size.width, height: aspectHeight) : CGSize(width: aspectWidth, height: size.height)
    }

    private var aspectRatio: CGFloat {
        return base.height == 0.0 ? 1.0 : base.width / base.height
    }
    
    
    func constrainedRect(for size: CGSize, anchor: CGPoint) -> CGRect {
        
        let unifiedAnchor = CGPoint(x: anchor.x.clamped(to: 0.0...1.0),
                                    y: anchor.y.clamped(to: 0.0...1.0))
        
        let x = unifiedAnchor.x * base.width - unifiedAnchor.x * size.width
        let y = unifiedAnchor.y * base.height - unifiedAnchor.y * size.height
        let r = CGRect(x: x, y: y, width: size.width, height: size.height)
        
        let ori = CGRect(origin: CGPoint.zero, size: base)
        return ori.intersection(r)
    }
}

extension CGRect {
    func scaled(_ scale: CGFloat) -> CGRect {
        return CGRect(x: origin.x * scale, y: origin.y * scale,
                      width: size.width * scale, height: size.height * scale)
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension Kingfisher where Base: Image {
    
    func beginContext(size: CGSize) -> CGContext? {
        #if os(macOS)
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height),
                bitsPerSample: cgImage?.bitsPerComponent ?? 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: NSCalibratedRGBColorSpace,
                bytesPerRow: 0,
                bitsPerPixel: 0) else
            {
                assertionFailure("[Kingfisher] Image representation cannot be created.")
                return nil
            }
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
                assertionFailure("[Kingfisher] Image contenxt cannot be created.")
                return nil
            }
            
            NSGraphicsContext.setCurrent(context)
            return context.cgContext
        #else
            UIGraphicsBeginImageContextWithOptions(size, false, scale)
            let context = UIGraphicsGetCurrentContext()
            context?.scaleBy(x: 1.0, y: -1.0)
            context?.translateBy(x: 0, y: -size.height)
            return context
        #endif
    }
    
    func endContext() {
        #if os(macOS)
            NSGraphicsContext.restoreGraphicsState()
        #else
            UIGraphicsEndImageContext()
        #endif
    }
    
    func draw(cgImage: CGImage?, to size: CGSize, draw: ()->()) -> Image {
        #if os(macOS)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: cgImage?.bitsPerComponent ?? 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: NSCalibratedRGBColorSpace,
            bytesPerRow: 0,
            bitsPerPixel: 0) else
        {
            assertionFailure("[Kingfisher] Image representation cannot be created.")
            return base
        }
        rep.size = size
        
        NSGraphicsContext.saveGraphicsState()
        
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.setCurrent(context)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        
        let outputImage = Image(size: size)
        outputImage.addRepresentation(rep)
        return outputImage
        #else
            
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw()
        return UIGraphicsGetImageFromCurrentImageContext() ?? base
        
        #endif
    }
    
    #if os(macOS)
    func fixedForRetinaPixel(cgImage: CGImage, to size: CGSize) -> Image {
        
        let image = Image(cgImage: cgImage, size: base.size)
        let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: size)
        
        return draw(cgImage: cgImage, to: self.size) {
            image.draw(in: rect, from: NSRect.zero, operation: .copy, fraction: 1.0)
        }
    }
    #endif
}

extension Float {
    var isEven: Bool {
        return truncatingRemainder(dividingBy: 2.0) == 0
    }
}

#if os(macOS)
extension NSBezierPath {
    convenience init(roundedRect rect: NSRect, topLeftRadius: CGFloat, topRightRadius: CGFloat,
         bottomLeftRadius: CGFloat, bottomRightRadius: CGFloat)
    {
        self.init()
        
        let maxCorner = min(rect.width, rect.height) / 2
        
        let radiusTopLeft = min(maxCorner, max(0, topLeftRadius))
        let radiustopRight = min(maxCorner, max(0, topRightRadius))
        let radiusbottomLeft = min(maxCorner, max(0, bottomLeftRadius))
        let radiusbottomRight = min(maxCorner, max(0, bottomRightRadius))
        
        guard !NSIsEmptyRect(rect) else {
            return
        }
        
        let topLeft = NSMakePoint(NSMinX(rect), NSMaxY(rect));
        let topRight = NSMakePoint(NSMaxX(rect), NSMaxY(rect));
        let bottomRight = NSMakePoint(NSMaxX(rect), NSMinY(rect));
        
        move(to: NSMakePoint(NSMidX(rect), NSMaxY(rect)))
        appendArc(from: topLeft, to: rect.origin, radius: radiusTopLeft)
        appendArc(from: rect.origin, to: bottomRight, radius: radiusbottomLeft)
        appendArc(from: bottomRight, to: topRight, radius: radiusbottomRight)
        appendArc(from: topRight, to: topLeft, radius: radiustopRight)
        close()
    }
    
    convenience init(roundedRect rect: NSRect, byRoundingCorners corners: RectCorner, radius: CGFloat) {
        let radiusTopLeft = corners.contains(.topLeft) ? radius : 0
        let radiusTopRight = corners.contains(.topRight) ? radius : 0
        let radiusBottomLeft = corners.contains(.bottomLeft) ? radius : 0
        let radiusBottomRight = corners.contains(.bottomRight) ? radius : 0
        
        self.init(roundedRect: rect, topLeftRadius: radiusTopLeft, topRightRadius: radiusTopRight,
                  bottomLeftRadius: radiusBottomLeft, bottomRightRadius: radiusBottomRight)
    }
}
    
#else
extension RectCorner {
    var uiRectCorner: UIRectCorner {
        
        var result: UIRectCorner = []
        
        if self.contains(.topLeft) { result.insert(.topLeft) }
        if self.contains(.topRight) { result.insert(.topRight) }
        if self.contains(.bottomLeft) { result.insert(.bottomLeft) }
        if self.contains(.bottomRight) { result.insert(.bottomRight) }
        
        return result
    }
}
#endif

// MARK: - Deprecated. Only for back compatibility.
extension Image {
    /**
     Normalize the image. This method does nothing in OS X.
     
     - returns: The image itself.
     */
    @available(*, deprecated,
    message: "Extensions directly on Image are deprecated. Use `kf.normalized` instead.",
    renamed: "kf.normalized")
    public func kf_normalized() -> Image {
        return kf.normalized
    }
    
    // MARK: - Round Corner
    
    /// Create a round corner image based on `self`.
    ///
    /// - parameter radius: The round corner radius of creating image.
    /// - parameter size:   The target size of creating image.
    /// - parameter scale:  The image scale of creating image.
    ///
    /// - returns: An image with round corner of `self`.
    ///
    /// - Note: This method only works for CG-based image.
    @available(*, deprecated,
    message: "Extensions directly on Image are deprecated. Use `kf.image(withRoundRadius:fit:scale:)` instead.",
    renamed: "kf.image")
    public func kf_image(withRoundRadius radius: CGFloat, fit size: CGSize, scale: CGFloat) -> Image {
        return kf.image(withRoundRadius: radius, fit: size)
    }
    
    // MARK: - Resize
    /// Resize `self` to an image of new size.
    ///
    /// - parameter size: The target size.
    ///
    /// - returns: An image with new size.
    ///
    /// - Note: This method only works for CG-based image.
    @available(*, deprecated,
    message: "Extensions directly on Image are deprecated. Use `kf.resize(to:)` instead.",
    renamed: "kf.resize")
    public func kf_resize(to size: CGSize) -> Image {
        return kf.resize(to: size)
    }
    
    // MARK: - Blur
    /// Create an image with blur effect based on `self`.
    ///
    /// - parameter radius: The blur radius should be used when creating blue.
    ///
    /// - returns: An image with blur effect applied.
    ///
    /// - Note: This method only works for CG-based image.
    @available(*, deprecated,
    message: "Extensions directly on Image are deprecated. Use `kf.blurred(withRadius:)` instead.",
    renamed: "kf.blurred")
    public func kf_blurred(withRadius radius: CGFloat) -> Image {
        return kf.blurred(withRadius: radius)
    }
    
    // MARK: - Overlay
    /// Create an image from `self` with a color overlay layer.
    ///
    /// - parameter color:    The color should be use to overlay.
    /// - parameter fraction: Fraction of input color. From 0.0 to 1.0. 0.0 means solid color, 1.0 means transparent overlay.
    ///
    /// - returns: An image with a color overlay applied.
    ///
    /// - Note: This method only works for CG-based image.
    @available(*, deprecated,
    message: "Extensions directly on Image are deprecated. Use `kf.overlaying(with:fraction:)` instead.",
    renamed: "kf.overlaying")
    public func kf_overlaying(with color: Color, fraction: CGFloat) -> Image {
        return kf.overlaying(with: color, fraction: fraction)
    }
    
    // MARK: - Tint
    
    /// Create an image from `self` with a color tint.
    ///
    /// - parameter color: The color should be used to tint `self`
    ///
    /// - returns: An image with a color tint applied.
    @available(*, deprecated,
    message: "Extensions directly on Image are deprecated. Use `kf.tinted(with:)` instead.",
    renamed: "kf.tinted")
    public func kf_tinted(with color: Color) -> Image {
        return kf.tinted(with: color)
    }
    
    // MARK: - Color Control
    
    /// Create an image from `self` with color control.
    ///
    /// - parameter brightness: Brightness changing to image.
    /// - parameter contrast:   Contrast changing to image.
    /// - parameter saturation: Saturation changing to image.
    /// - parameter inputEV:    InputEV changing to image.
    ///
    /// - returns: An image with color control applied.
    @available(*, deprecated,
    message: "Extensions directly on Image are deprecated. Use `kf.adjusted` instead.",
    renamed: "kf.adjusted")
    public func kf_adjusted(brightness: CGFloat, contrast: CGFloat, saturation: CGFloat, inputEV: CGFloat) -> Image {
        return kf.adjusted(brightness: brightness, contrast: contrast, saturation: saturation, inputEV: inputEV)
    }
}

extension Kingfisher where Base: Image {
    @available(*, deprecated,
    message: "`scale` is not used. Use the version without scale instead. (Remove the `scale` argument)")
    public func image(withRoundRadius radius: CGFloat, fit size: CGSize, scale: CGFloat) -> Image {
        return image(withRoundRadius: radius, fit: size)
    }
}
// Toucan.swift
//
// Copyright (c) 2014-2016 Gavin Bunney, Simple Labs (http://thesimplelab.co)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import UIKit
import CoreGraphics

/**
 Toucan - Fabulous Image Processing in Swift.
 
 The Toucan class provides two methods of interaction - either through an instance, wrapping an single image,
 or through the static functions, providing an image for each invocation.
 
 This allows for some flexible usage. Using static methods when you need a single operation:
 let resizedImage = Toucan.resize(myImage, size: CGSize(width: 100, height: 150))
 
 Or create an instance for easy method chaining:
 let resizedAndMaskedImage = Toucan(withImage: myImage).resize(CGSize(width: 100, height: 150)).maskWithEllipse().image
 */
public class Toucan : NSObject {
    
    public var image : UIImage
    
    public init(image withImage: UIImage) {
        self.image = withImage
    }
    
    // MARK: - Resize
    
    /**
     Resize the contained image to the specified size. Depending on what fitMode is supplied, the image
     may be clipped, cropped or scaled. @see documentation on FitMode.
     
     The current image on this toucan instance is replaced with the resized image.
     
     - parameter size:    Size to resize the image to
     - parameter fitMode: How to handle the image resizing process
     
     - returns: Self, allowing method chaining
     */
    public func resize(_ size: CGSize, fitMode: Toucan.Resize.FitMode = .clip) -> Toucan {
        self.image = Toucan.Resize.resizeImage(self.image, size: size, fitMode: fitMode)
        return self
    }
    
    /**
     Resize the contained image to the specified size by resizing the image to fit
     within the width and height boundaries without cropping or scaling the image.
     
     The current image on this toucan instance is replaced with the resized image.
     
     - parameter size:    Size to resize the image to
     
     - returns: Self, allowing method chaining
     */
    @objc
    public func resizeByClipping(_ size: CGSize) -> Toucan {
        self.image = Toucan.Resize.resizeImage(self.image, size: size, fitMode: .clip)
        return self
    }
    
    /**
     Resize the contained image to the specified size by resizing the image to fill the
     width and height boundaries and crops any excess image data.
     The resulting image will match the width and height constraints without scaling the image.
     
     The current image on this toucan instance is replaced with the resized image.
     
     - parameter size:    Size to resize the image to
     
     - returns: Self, allowing method chaining
     */
    @objc
    public func resizeByCropping(_ size: CGSize) -> Toucan {
        self.image = Toucan.Resize.resizeImage(self.image, size: size, fitMode: .crop)
        return self
    }
    
    /**
     Resize the contained image to the specified size by scaling the image to fit the
     constraining dimensions exactly.
     
     The current image on this toucan instance is replaced with the resized image.
     
     - parameter size:    Size to resize the image to
     
     - returns: Self, allowing method chaining
     */
    @objc
    public func resizeByScaling(_ size: CGSize) -> Toucan {
        self.image = Toucan.Resize.resizeImage(self.image, size: size, fitMode: .scale)
        return self
    }
    
    /**
     Container struct for all things Resize related
     */
    public struct Resize {
        
        /**
         FitMode drives the resizing process to determine what to do with an image to
         make it fit the given size bounds.
         
         - Clip:  Resizes the image to fit within the width and height boundaries without cropping or scaling the image.
         
         - Crop:  Resizes the image to fill the width and height boundaries and crops any excess image data.
         
         - Scale: Scales the image to fit the constraining dimensions exactly.
         */
        public enum FitMode {
            /**
             Resizes the image to fit within the width and height boundaries without cropping or scaling the image.
             The resulting image is assured to match one of the constraining dimensions, while
             the other dimension is altered to maintain the same aspect ratio of the input image.
             */
            case clip
            
            /**
             Resizes the image to fill the width and height boundaries and crops any excess image data.
             The resulting image will match the width and height constraints without scaling the image.
             */
            case crop
            
            /**
             Scales the image to fit the constraining dimensions exactly.
             */
            case scale
        }
        
        /**
         Resize an image to the specified size. Depending on what fitMode is supplied, the image
         may be clipped, cropped or scaled. @see documentation on FitMode.
         
         - parameter image:   Image to Resize
         - parameter size:    Size to resize the image to
         - parameter fitMode: How to handle the image resizing process
         
         - returns: Resized image
         */
        public static func resizeImage(_ image: UIImage, size: CGSize, fitMode: FitMode = .clip) -> UIImage {
            
            let imgRef = Util.CGImageWithCorrectOrientation(image)
            let originalWidth  = CGFloat(imgRef.width)
            let originalHeight = CGFloat(imgRef.height)
            let widthRatio = size.width / originalWidth
            let heightRatio = size.height / originalHeight
            
            let scaleRatio = widthRatio > heightRatio ? widthRatio : heightRatio
            
            let resizedImageBounds = CGRect(x: 0, y: 0, width: round(originalWidth * scaleRatio), height: round(originalHeight * scaleRatio))
            let resizedImage = Util.drawImageInBounds(image, bounds: resizedImageBounds)
            
            switch (fitMode) {
            case .clip:
                return resizedImage
            case .crop:
                let croppedRect = CGRect(x: (resizedImage.size.width - size.width) / 2,
                                         y: (resizedImage.size.height - size.height) / 2,
                                         width: size.width, height: size.height)
                return Util.croppedImageWithRect(resizedImage, rect: croppedRect)
            case .scale:
                return Util.drawImageInBounds(resizedImage, bounds: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }
        }
    }
    
    // MARK: - Mask
    
    /**
     Mask the contained image with another image mask.
     Note that the areas in the original image that correspond to the black areas of the mask
     show through in the resulting image. The areas that correspond to the white areas of
     the mask aren’t painted. The areas that correspond to the gray areas in the mask are painted
     using an intermediate alpha value that’s equal to 1 minus the image mask sample value.
     
     - parameter maskImage: Image Mask to apply to the Image
     
     - returns: Self, allowing method chaining
     */
    public func maskWithImage(maskImage : UIImage)  -> Toucan {
        self.image = Toucan.Mask.maskImageWithImage(self.image, maskImage: maskImage)
        return self
    }
    
    /**
     Mask the contained image with an ellipse.
     Allows specifying an additional border to draw on the clipped image.
     For a circle, ensure the image width and height are equal!
     
     - parameter borderWidth: Optional width of the border to apply - default 0
     - parameter borderColor: Optional color of the border - default White
     
     - returns: Self, allowing method chaining
     */
    public func maskWithEllipse(borderWidth: CGFloat = 0, borderColor: UIColor = UIColor.white) -> Toucan {
        self.image = Toucan.Mask.maskImageWithEllipse(self.image, borderWidth: borderWidth, borderColor: borderColor)
        return self
    }
    
    /**
     Mask the contained image with a path (UIBezierPath) that will be scaled to fit the image.
     
     - parameter path: UIBezierPath to mask the image
     
     - returns: Self, allowing method chaining
     */
    public func maskWithPath(path: UIBezierPath) -> Toucan {
        self.image = Toucan.Mask.maskImageWithPath(self.image, path: path)
        return self
    }
    
    /**
     Mask the contained image with a path (UIBezierPath) which is provided via a closure.
     
     - parameter path: closure that returns a UIBezierPath. Using a closure allows the user to provide the path after knowing the size of the image
     
     - returns: Self, allowing method chaining
     */
    public func maskWithPathClosure(path: (_ rect: CGRect) -> (UIBezierPath)) -> Toucan {
        self.image = Toucan.Mask.maskImageWithPathClosure(self.image, pathInRect: path)
        return self
    }
    
    /**
     Mask the contained image with a rounded rectangle border.
     Allows specifying an additional border to draw on the clipped image.
     
     - parameter cornerRadius: Radius of the rounded rect corners
     - parameter borderWidth:  Optional width of border to apply - default 0
     - parameter borderColor:  Optional color of the border - default White
     
     - returns: Self, allowing method chaining
     */
    public func maskWithRoundedRect(cornerRadius: CGFloat, borderWidth: CGFloat = 0, borderColor: UIColor = UIColor.white) -> Toucan {
        self.image = Toucan.Mask.maskImageWithRoundedRect(self.image, cornerRadius: cornerRadius, borderWidth: borderWidth, borderColor: borderColor)
        return self
    }
    
    /**
     Container struct for all things Mask related
     */
    public struct Mask {
        
        /**
         Mask the given image with another image mask.
         Note that the areas in the original image that correspond to the black areas of the mask
         show through in the resulting image. The areas that correspond to the white areas of
         the mask aren’t painted. The areas that correspond to the gray areas in the mask are painted
         using an intermediate alpha value that’s equal to 1 minus the image mask sample value.
         
         - parameter image:     Image to apply the mask to
         - parameter maskImage: Image Mask to apply to the Image
         
         - returns: Masked image
         */
        public static func maskImageWithImage(_ image: UIImage, maskImage: UIImage) -> UIImage {
            
            let imgRef = Util.CGImageWithCorrectOrientation(image)
            let maskRef = maskImage.cgImage
            
            let mask = CGImage(maskWidth: (maskRef?.width)!,
                               height: (maskRef?.height)!,
                               bitsPerComponent: (maskRef?.bitsPerComponent)!,
                               bitsPerPixel: (maskRef?.bitsPerPixel)!,
                               bytesPerRow: (maskRef?.bytesPerRow)!,
                               provider: (maskRef?.dataProvider!)!, decode: nil, shouldInterpolate: false);
            
            let masked = imgRef.masking(mask!);
            
            return Util.drawImageWithClosure(size: image.size) { (size: CGSize, context: CGContext) -> () in
                
                // need to flip the transform matrix, CoreGraphics has (0,0) in lower left when drawing image
                context.scaleBy(x: 1, y: -1)
                context.translateBy(x: 0, y: -size.height)
                
                context.draw(masked!, in: CGRect(x: 0, y: 0, width: size.width, height: size.height));
            }
        }
        
        /**
         Mask the given image with an ellipse.
         Allows specifying an additional border to draw on the clipped image.
         For a circle, ensure the image width and height are equal!
         
         - parameter image:       Image to apply the mask to
         - parameter borderWidth: Optional width of the border to apply - default 0
         - parameter borderColor: Optional color of the border - default White
         
         - returns: Masked image
         */
        public static func maskImageWithEllipse(_ image: UIImage,
                                                borderWidth: CGFloat = 0, borderColor: UIColor = UIColor.white) -> UIImage {
            
            let imgRef = Util.CGImageWithCorrectOrientation(image)
            let size = CGSize(width: CGFloat(imgRef.width) / image.scale, height: CGFloat(imgRef.height) / image.scale)
            
            return Util.drawImageWithClosure(size: size) { (size: CGSize, context: CGContext) -> () in
                
                let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                
                context.addEllipse(in: rect)
                context.clip()
                image.draw(in: rect)
                
                if (borderWidth > 0) {
                    context.setStrokeColor(borderColor.cgColor);
                    context.setLineWidth(borderWidth);
                    context.addEllipse(in: CGRect(x: borderWidth / 2,
                                                  y: borderWidth / 2,
                                                  width: size.width - borderWidth,
                                                  height: size.height - borderWidth));
                    context.strokePath();
                }
            }
        }
        
        /**
         Mask the given image with a path(UIBezierPath) that will be scaled to fit the image.
         
         - parameter image:       Image to apply the mask to
         - parameter path: UIBezierPath to make as the mask
         
         - returns: Masked image
         */
        public static func maskImageWithPath(_ image: UIImage,
                                             path: UIBezierPath) -> UIImage {
            
            let imgRef = Util.CGImageWithCorrectOrientation(image)
            let size = CGSize(width: CGFloat(imgRef.width) / image.scale, height: CGFloat(imgRef.height) / image.scale)
            
            return Util.drawImageWithClosure(size: size) { (size: CGSize, context: CGContext) -> () in
                
                let boundSize = path.bounds.size
                
                let pathRatio = boundSize.width / boundSize.height
                let imageRatio = size.width / size.height
                
                
                if pathRatio > imageRatio {
                    //scale based on width
                    let scale = size.width / boundSize.width
                    path.apply(CGAffineTransform(scaleX: scale, y: scale))
                    path.apply(CGAffineTransform(translationX: 0, y: (size.height - path.bounds.height) / 2.0))
                } else {
                    //scale based on height
                    let scale = size.height / boundSize.height
                    path.apply(CGAffineTransform(scaleX: scale, y: scale))
                    path.apply(CGAffineTransform(translationX: (size.width - path.bounds.width) / 2.0, y: 0))
                }
                
                let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                
                context.addPath(path.cgPath)
                context.clip()
                image.draw(in: rect)
            }
        }
        
        /**
         Mask the given image with a path(UIBezierPath) provided via a closure. This allows the user to get the size of the image before computing their path variable.
         
         - parameter image:       Image to apply the mask to
         - parameter path: UIBezierPath to make as the mask
         
         - returns: Masked image
         */
        public static func maskImageWithPathClosure(_ image: UIImage,
                                                    pathInRect:(_ rect: CGRect) -> (UIBezierPath)) -> UIImage {
            
            let imgRef = Util.CGImageWithCorrectOrientation(image)
            let size = CGSize(width: CGFloat(imgRef.width) / image.scale, height: CGFloat(imgRef.height) / image.scale)
            
            return maskImageWithPath(image, path: pathInRect(CGRect(x: 0, y: 0, width: size.width, height: size.height)))
        }
        
        /**
         Mask the given image with a rounded rectangle border.
         Allows specifying an additional border to draw on the clipped image.
         
         - parameter image:        Image to apply the mask to
         - parameter cornerRadius: Radius of the rounded rect corners
         - parameter borderWidth:  Optional width of border to apply - default 0
         - parameter borderColor:  Optional color of the border - default White
         
         - returns: Masked image
         */
        public static func maskImageWithRoundedRect(_ image: UIImage, cornerRadius: CGFloat,
                                                    borderWidth: CGFloat = 0, borderColor: UIColor = UIColor.white) -> UIImage {
            
            let imgRef = Util.CGImageWithCorrectOrientation(image)
            let size = CGSize(width: CGFloat(imgRef.width) / image.scale, height: CGFloat(imgRef.height) / image.scale)
            
            return Util.drawImageWithClosure(size: size) { (size: CGSize, context: CGContext) -> () in
                
                let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                
                UIBezierPath(roundedRect:rect, cornerRadius: cornerRadius).addClip()
                image.draw(in: rect)
                
                if (borderWidth > 0) {
                    context.setStrokeColor(borderColor.cgColor);
                    context.setLineWidth(borderWidth);
                    
                    let borderRect = CGRect(x: 0, y: 0,
                                            width: size.width, height: size.height)
                    
                    let borderPath = UIBezierPath(roundedRect: borderRect, cornerRadius: cornerRadius)
                    borderPath.lineWidth = borderWidth * 2
                    borderPath.stroke()
                }
            }
        }
    }
    
    // MARK: - Layer
    
    /**
     Overlay an image ontop of the current image.
     
     - parameter image:        Image to be on the bottom layer
     - parameter overlayImage: Image to be on the top layer, i.e. drawn on top of image
     - parameter overlayFrame: Frame of the overlay image
     
     - returns: Self, allowing method chaining
     */
    public func layerWithOverlayImage(_ overlayImage: UIImage, overlayFrame: CGRect) -> Toucan {
        self.image = Toucan.Layer.overlayImage(self.image, overlayImage:overlayImage, overlayFrame:overlayFrame)
        return self
    }
    
    /**
     Container struct for all things Layer related.
     */
    public struct Layer {
        
        /**
         Overlay the given image into a new layout ontop of the image.
         
         - parameter image:        Image to be on the bottom layer
         - parameter overlayImage: Image to be on the top layer, i.e. drawn on top of image
         - parameter overlayFrame: Frame of the overlay image
         
         - returns: Masked image
         */
        public static func overlayImage(_ image: UIImage, overlayImage: UIImage, overlayFrame: CGRect) -> UIImage {
            
            let imgRef = Util.CGImageWithCorrectOrientation(image)
            let size = CGSize(width: CGFloat(imgRef.width) / image.scale, height: CGFloat(imgRef.height) / image.scale)
            
            return Util.drawImageWithClosure(size: size) { (size: CGSize, context: CGContext) -> () in
                
                let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                
                image.draw(in: rect)
                overlayImage.draw(in: overlayFrame);
            }
        }
    }
    
    /**
     Container struct for internally used utility functions.
     */
    internal struct Util {
        
        /**
         Get the CGImage of the image with the orientation fixed up based on EXF data.
         This helps to normalise input images to always be the correct orientation when performing
         other core graphics tasks on the image.
         
         - parameter image: Image to create CGImageRef for
         
         - returns: CGImageRef with rotated/transformed image context
         */
        static func CGImageWithCorrectOrientation(_ image : UIImage) -> CGImage {
            
            if (image.imageOrientation == UIImageOrientation.up) {
                return image.cgImage!
            }
            
            var transform : CGAffineTransform = CGAffineTransform.identity;
            
            switch (image.imageOrientation) {
            case UIImageOrientation.right, UIImageOrientation.rightMirrored:
                transform = transform.translatedBy(x: 0, y: image.size.height)
                transform = transform.rotated(by: CGFloat(-1.0 * M_PI_2))
                break
            case UIImageOrientation.left, UIImageOrientation.leftMirrored:
                transform = transform.translatedBy(x: image.size.width, y: 0)
                transform = transform.rotated(by: CGFloat(M_PI_2))
                break
            case UIImageOrientation.down, UIImageOrientation.downMirrored:
                transform = transform.translatedBy(x: image.size.width, y: image.size.height)
                transform = transform.rotated(by: CGFloat(M_PI))
                break
            default:
                break
            }
            
            switch (image.imageOrientation) {
            case UIImageOrientation.rightMirrored, UIImageOrientation.leftMirrored:
                transform = transform.translatedBy(x: image.size.height, y: 0);
                transform = transform.scaledBy(x: -1, y: 1);
                break
            case UIImageOrientation.downMirrored, UIImageOrientation.upMirrored:
                transform = transform.translatedBy(x: image.size.width, y: 0);
                transform = transform.scaledBy(x: -1, y: 1);
                break
            default:
                break
            }
            
            let contextWidth : Int
            let contextHeight : Int
            
            switch (image.imageOrientation) {
            case UIImageOrientation.left, UIImageOrientation.leftMirrored,
                 UIImageOrientation.right, UIImageOrientation.rightMirrored:
                contextWidth = (image.cgImage?.height)!
                contextHeight = (image.cgImage?.width)!
                break
            default:
                contextWidth = (image.cgImage?.width)!
                contextHeight = (image.cgImage?.height)!
                break
            }
            
            let context : CGContext = CGContext(data: nil, width: contextWidth, height: contextHeight,
                                                bitsPerComponent: image.cgImage!.bitsPerComponent,
                                                bytesPerRow: image.cgImage!.bytesPerRow,
                                                space: image.cgImage!.colorSpace!,
                                                bitmapInfo: image.cgImage!.bitmapInfo.rawValue)!;
            
            context.concatenate(transform);
            context.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: CGFloat(contextWidth), height: CGFloat(contextHeight)));
            
            let cgImage = context.makeImage();
            return cgImage!;
        }
        
        /**
         Draw the image within the given bounds (i.e. resizes)
         
         - parameter image:  Image to draw within the given bounds
         - parameter bounds: Bounds to draw the image within
         
         - returns: Resized image within bounds
         */
        static func drawImageInBounds(_ image: UIImage, bounds : CGRect) -> UIImage {
            return drawImageWithClosure(size: bounds.size) { (size: CGSize, context: CGContext) -> () in
                image.draw(in: bounds)
            };
        }
        
        /**
         Crop the image within the given rect (i.e. resizes and crops)
         
         - parameter image: Image to clip within the given rect bounds
         - parameter rect:  Bounds to draw the image within
         
         - returns: Resized and cropped image
         */
        static func croppedImageWithRect(_ image: UIImage, rect: CGRect) -> UIImage {
            return drawImageWithClosure(size: rect.size) { (size: CGSize, context: CGContext) -> () in
                let drawRect = CGRect(x: -rect.origin.x, y: -rect.origin.y, width: image.size.width, height: image.size.height)
                context.clip(to: CGRect(x: 0, y: 0, width: rect.size.width, height: rect.size.height))
                image.draw(in: drawRect)
            };
        }
        
        /**
         Closure wrapper around image context - setting up, ending and grabbing the image from the context.
         
         - parameter size:    Size of the graphics context to create
         - parameter closure: Closure of magic to run in a new context
         
         - returns: Image pulled from the end of the closure
         */
        static func drawImageWithClosure(size: CGSize!, closure: (_ size: CGSize, _ context: CGContext) -> ()) -> UIImage {
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            closure(size, UIGraphicsGetCurrentContext()!)
            let image : UIImage = UIGraphicsGetImageFromCurrentImageContext()!
            UIGraphicsEndImageContext()
            return image
        }
    }
}
