import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes `CGImage`s as JPEG `Data` at the configured quality.
///
/// Encoding happens on whatever queue the caller is on; callers should keep
/// the encoder off the main actor.
struct CameraEncoder: Sendable {
    var quality: Double

    init(quality: Double = 0.7) {
        self.quality = max(0.05, min(quality, 1.0))
    }

    func encode(cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    func encode(ciImage: CIImage, context: CIContext) -> Data? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return encode(cgImage: cgImage)
    }
}
