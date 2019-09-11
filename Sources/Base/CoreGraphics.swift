// Copyright (c) 2017 Yandex LLC. All rights reserved.
// Author: Alfred Zien <zienag@yandex-team.ru>

import CoreGraphics
import CoreServices
import ImageIO

public typealias RGBAPixel = RGBAColor<UInt8>

extension RGBAPixel {
  public init<T: Sequence>(
    bufferPiece: T
  ) where T.Element == UInt8 {
    var it = bufferPiece.makeIterator()
    red = it.next()!
    green = it.next()!
    blue = it.next()!
    alpha = it.next()!
  }
}

public class RGBABuffer {
  public let size: CGIntSize
  public typealias BufferPieces = Splitted<UnsafeBufferPointer<UInt8>>
  public typealias SlicedBufferPieces = Slice<BufferPieces>
  public typealias Pixelated<T: Collection> = LazyMapCollection<T, RGBAPixel>
  public typealias Lines = Splitted<Pixelated<BufferPieces>>

  public let pixels: LazyMapSequence<Lines, Pixelated<SlicedBufferPieces>>

  private let free: () -> Void

  public init(image: CGImage) {
    let ctx = CGContext.bitmapRGBContext(size: image.intSize)
    ctx.draw(image, in: image.intSize.rect)
    let raw = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let size = image.intSize
    let bytesPerRow = ctx.bytesPerRow
    let length = size.height * bytesPerRow
    let pixelsPerRow = bytesPerRow / 4
    let buffer = UnsafeBufferPointer(start: raw, count: length)
    free = { withExtendedLifetime(ctx) { _ in } }
    pixels = buffer
      .splitBy(subSize: 4)
      .lazy
      .map(RGBAPixel.init)
      .splitBy(subSize: pixelsPerRow)
      .lazy
      .map { $0.dropLast(pixelsPerRow - size.width) }
    self.size = size
  }

  deinit {
    free()
  }
}

// Geometry

public struct CGIntSize: Equatable {
  public let width: Int
  public let height: Int
  public static func size(w: Int, h: Int) -> CGIntSize {
    return CGIntSize(width: w, height: h)
  }

  public var rect: CGRect {
    return CGRect(x: 0, y: 0, width: width, height: height)
  }

  public static func from(cgsize: CGSize) -> CGIntSize {
    return CGIntSize(width: Int(cgsize.width), height: Int(cgsize.height))
  }

  public static func union(lhs: CGIntSize, rhs: CGIntSize) -> CGIntSize {
    return CGIntSize(
      width: max(lhs.width, rhs.width),
      height: max(lhs.height, rhs.height)
    )
  }
}

extension CGRect {
  public var x: CGFloat {
    return origin.x
  }

  public var y: CGFloat {
    return origin.y
  }
}

extension CGSize {
  public static func square(_ dim: CGFloat) -> CGSize {
    return .init(width: dim, height: dim)
  }
}

extension CGAffineTransform {
  public static func scale(_ scale: CGFloat) -> CGAffineTransform {
    return CGAffineTransform(scaleX: scale, y: scale)
  }

  public static func invertYAxis(height: CGFloat) -> CGAffineTransform {
    return CGAffineTransform(scaleX: 1, y: -1).concatenating(.init(translationX: 0, y: height))
  }
}

extension Double {
  public var cgfloat: CGFloat {
    return CGFloat(self)
  }
}

// PDF

extension CGPDFDocument {
  public var pages: [CGPDFPage] {
    return (1...numberOfPages).compactMap(page(at:))
  }
}

extension CGPDFPage {
  public func render(scale: CGFloat) -> CGImage? {
    let s = getBoxRect(.mediaBox).size
    let ctxSize = s.applying(.scale(scale))
    let ctx = CGContext.bitmapRGBContext(size: ctxSize)
    ctx.setAllowsAntialiasing(false)
    ctx.scaleBy(x: scale, y: scale)
    ctx.drawPDFPage(self)
    return ctx.makeImage()
  }
}

// Color space

extension CGColorSpace {
  public static var deviceRGB: CGColorSpace {
    return CGColorSpaceCreateDeviceRGB()
  }
}

// Context

extension CGContext {
  public static func bitmapRGBContext(size: CGSize) -> CGContext {
    return bitmapRGBContext(size: .from(cgsize: size))
  }

  public static func bitmapRGBContext(size: CGIntSize) -> CGContext {
    return CGContext(
      data: nil,
      width: size.width,
      height: size.height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: .deviceRGB,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
  }
}

// Image

extension CGImage {
  public var intSize: CGIntSize {
    return .size(w: width, h: height)
  }

  public static func diff(lhs: CGImage, rhs: CGImage) -> CGImage {
    let size = CGIntSize.union(lhs: lhs.intSize, rhs: rhs.intSize)
    let ctx = CGContext.bitmapRGBContext(size: size)
    ctx.draw(lhs, in: lhs.intSize.rect)
    ctx.setAlpha(0.5)
    ctx.setBlendMode(.difference)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.draw(rhs, in: rhs.intSize.rect)
    ctx.setFillColor(.white)
    ctx.endTransparencyLayer()
    return ctx.makeImage()!
  }

  public enum CGImageWriteError: Error {
    case failedToCreateDestination
    case failedDestinationFinalize
  }

  public func write(fileURL: CFURL) throws {
    guard let destination = CGImageDestinationCreateWithURL(fileURL, kUTTypePNG, 1, nil)
    else { throw CGImageWriteError.failedDestinationFinalize }
    CGImageDestinationAddImage(destination, self, nil)
    guard CGImageDestinationFinalize(destination)
    else { throw CGImageWriteError.failedDestinationFinalize }
  }

  public func redraw(with background: CGColor) -> CGImage {
    let size = intSize
    let ctx = CGContext.bitmapRGBContext(size: size)
    ctx.setFillColor(background)
    ctx.fill(size.rect)
    ctx.draw(self, in: size.rect)
    return ctx.makeImage()!
  }
}

extension CGPath {
  public static func make(_ builder: (CGMutablePath) -> Void) -> CGPath {
    let mutable = CGMutablePath()
    builder(mutable)
    return mutable.copy()!
  }
}
