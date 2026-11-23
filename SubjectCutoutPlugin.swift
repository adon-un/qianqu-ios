import Foundation
import UIKit
import Vision
import CoreImage
import Capacitor

/**
 * 用 iOS 17+ 的 Vision「前景主体」能力抠图。
 * 输入：base64 PNG
 * 输出：去掉背景、保留主体的 base64 PNG（尺寸与输入一致）
 */
@objc(SubjectCutoutPlugin)
public class SubjectCutoutPlugin: CAPPlugin, CAPBridgedPlugin {

    public let identifier = "SubjectCutoutPlugin"
    public let jsName = "SubjectCutout"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "cutout", returnType: CAPPluginReturnPromise)
    ]

    @objc public func cutout(_ call: CAPPluginCall) {
        guard let b64 = call.getString("image"),
              let data = Data(base64Encoded: b64),
              let ui = UIImage(data: data),
              let cg = ui.qc_normalizedCGImage() else {
            call.reject("INVALID_IMAGE")
            return
        }

        guard #available(iOS 17.0, *) else {
            call.reject("IOS_TOO_OLD")
            return
        }

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()

        do {
            try handler.perform([request])

            guard let result = request.results?.first,
                  !result.allInstances.isEmpty else {
                call.reject("NO_SUBJECT")
                return
            }

            let maskBuffer = try result.generateScaledMaskForImage(
                forInstances: result.allInstances,
                from: handler
            )

            let maskCI = CIImage(cvPixelBuffer: maskBuffer)
            let srcCI = CIImage(cgImage: cg)

            guard let blend = CIFilter(name: "CIBlendWithMask") else {
                call.reject("NO_FILTER")
                return
            }
            blend.setValue(srcCI, forKey: kCIInputImageKey)
            blend.setValue(maskCI, forKey: kCIInputMaskImageKey)

            guard let outCI = blend.outputImage else {
                call.reject("NO_OUTPUT")
                return
            }

            let ciContext = CIContext(options: [.useSoftwareRenderer: false])
            guard let outCG = ciContext.createCGImage(outCI, from: srcCI.extent) else {
                call.reject("RENDER_FAIL")
                return
            }

            guard let png = UIImage(cgImage: outCG).pngData() else {
                call.reject("PNG_FAIL")
                return
            }

            call.resolve(["image": "data:image/png;base64," + png.base64EncodedString()])
        } catch {
            call.reject("VISION_FAIL: \(error.localizedDescription)")
        }
    }
}

extension UIImage {
    /// 把 EXIF 方向烘进像素，避免 Vision 拿到的图是躺着的
    func qc_normalizedCGImage() -> CGImage? {
        if imageOrientation == .up, let cg = cgImage {
            return cg
        }
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        fmt.opaque = false
        let rect = CGRect(origin: .zero, size: size)
        let redrawn = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            self.draw(in: rect)
        }
        return redrawn.cgImage
    }
}
