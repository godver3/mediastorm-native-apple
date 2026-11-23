import CoreImage.CIFilterBuiltins
import SwiftUI

/// A QR code for `value`, drawn crisp (nearest-neighbour) on a white quiet zone.
struct QRCodeView: View {
    let value: String
    var size: CGFloat = 260

    var body: some View {
        Group {
            if let image = Self.image(value) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
            } else {
                Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .padding(size * 0.06)
        .frame(width: size, height: size)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("QR code")
    }

    static func image(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
