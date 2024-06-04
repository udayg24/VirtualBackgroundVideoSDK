// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import ARKit
import CoreImage
import CoreImage.CIFilterBuiltins
import WebRTC

public protocol VideoSDKVideoProcessor {
     func onFrameReceived(frame: RTCVideoFrame) -> RTCVideoFrame?
}

public class VideoSDKBackgroundProcessor: VideoSDKVideoProcessor {

    private var backgroundci: CIImage?
    
    public init(backgroundSource: URL) {
        downloadImage(from: backgroundSource){ image in
            if let image = image {
                self.backgroundci = image
            } else {
                print("Error downloading image")
            }
        }
    }
    
    public func onFrameReceived(frame: RTCVideoFrame) -> RTCVideoFrame? {
        let buffer = frame.buffer as! RTCCVPixelBuffer
        let pixelBuffer = buffer.pixelBuffer
        
        // Perform person segmentation
        if #available(iOS 15.0, *) {
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .balanced
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            
            do {
                try requestHandler.perform([request])
                //                    request.qualityLevel = .accurate
                request.outputPixelFormat = kCVPixelFormatType_OneComponent8
                guard let result = request.results?.first as? VNPixelBufferObservation else {
                    return nil
                }
                
                let maskPixelBuffer = result.pixelBuffer
                // Composite the image with the virtual background
                if let compositedPixelBuffer = compositeImage(originalPixelBuffer: pixelBuffer, maskPixelBuffer: maskPixelBuffer) {
                    // Create RTCVideoFrame from the composited pixel buffer
                    let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: compositedPixelBuffer)
                    let rtcVideoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: frame.rotation, timeStampNs: frame.timeStampNs)
                    //                self.meeting?.sendProcessedFrame(frame: rtcVideoFrame)
                    return rtcVideoFrame;
                } else {
                }
            } catch {
                print("Error performing person segmentation request: \(error)")
            }
        }
        return nil
    }
    
    public func changeBackground(backgroundSource: URL) {
        downloadImage(from: backgroundSource) { image in
            if let image = image {
                self.backgroundci = image
            }
            else {
                return
            }
        }
    }
    
    @available(iOS 13.0, *)
    func compositeImage(originalPixelBuffer: CVPixelBuffer, maskPixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: originalPixelBuffer)
        let maskCIImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        
        let maskScaleX = ciImage.extent.width / maskCIImage.extent.width
        let maskScaleY = ciImage.extent.height / maskCIImage.extent.height
        let maskScaled =  maskCIImage.transformed(by: __CGAffineTransformMake(maskScaleX, 0, 0, maskScaleY, 0, 0))
        
        guard let backgroundCIImage = self.backgroundci else {
            return nil
        }
        let backgroundScaleX = ciImage.extent.width / backgroundCIImage.extent.width
        let backgroundScaleY = ciImage.extent.height / backgroundCIImage.extent.height
        
        let backgroundScaled =  backgroundCIImage.transformed(by: __CGAffineTransformMake(backgroundScaleX, 0, 0, backgroundScaleY, 0, 0))
        
        //        let filter = CIFilter(name: "CIBlendWithMask")
        //
        ////        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        //        filter?.setValue(maskCIImage, forKey: kCIInputMaskImageKey)
        //        filter?.setValue(backgroundCIImage, forKey: kCIInputBackgroundImageKey)
        //
        //        guard let outputImage = filter?.outputImage else { return nil }
        
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = ciImage
        blendFilter.backgroundImage = backgroundScaled
        blendFilter.maskImage = maskScaled
        
        let blendedImage = blendFilter.outputImage
        let ciContext = CIContext(options: nil)
        let filteredImageRef = ciContext.createCGImage(blendedImage!, from: blendedImage!.extent)
        let maskDisplayRef = ciContext.createCGImage(maskScaled, from: maskScaled.extent)
        
        var outputPixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
             kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        let width = Int(blendedImage!.extent.width)
        let height = Int(blendedImage!.extent.height)
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs, &outputPixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer1 = outputPixelBuffer else {
            return nil
        }
        ciContext.render(blendedImage!, to: buffer1)
        return buffer1
    }
    
    func downloadImage(from url: URL, completion: @escaping (CIImage?) -> Void) {
        DispatchQueue.global().async {
            do {
                let imageData = try Data(contentsOf: url)
                let image = CIImage(data: imageData)
                DispatchQueue.main.async {
                    completion(image)
                }
            } catch {
                completion(nil)
            }
        }
    }
}
