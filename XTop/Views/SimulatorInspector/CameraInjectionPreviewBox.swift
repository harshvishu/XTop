import AppKit
import SwiftUI

/// A small self-contained preview that runs the built-in TestPatternSource
/// and renders its frames in a fixed square box. Lets the user verify the
/// frame source pipeline (encode → CGImage → render) works on the Mac side
/// independently of the simulator/DYLD shim path.
struct CameraInjectionPreviewBox: View {
    @State private var model = PreviewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text("Preview (test pattern)")
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack {
                Rectangle()
                    .fill(Color.black)

                if let image = model.image {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .frame(width: 180, height: 180)
            .clipShape(.rect(cornerRadius: DesignSystem.Radius.row))

            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "circle.fill")
                    .foregroundStyle(model.image == nil ? .gray : .green)
                    .font(.system(size: 8))
                Text(model.image == nil ? "Starting…" : "Live · \(model.frameCount) frames")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .task {
            await model.start()
        }
        .onDisappear {
            Task { await model.stop() }
        }
    }
}

@MainActor
@Observable
private final class PreviewModel {
    private(set) var image: CGImage?
    private(set) var frameCount: Int = 0
    private let source = TestPatternSource()
    private var started = false

    func start() async {
        guard !started else { return }
        started = true
        do {
            try await source.start { [weak self] frame in
                guard let self else { return }
                guard let provider = CGDataProvider(data: frame.jpegData as CFData),
                      let cgImage = CGImage(
                        jpegDataProviderSource: provider,
                        decode: nil,
                        shouldInterpolate: false,
                        intent: .defaultIntent
                      )
                else { return }
                Task { @MainActor in
                    self.image = cgImage
                    self.frameCount &+= 1
                }
            }
        } catch {
            // TestPatternSource never throws, but be defensive.
            started = false
        }
    }

    func stop() async {
        await source.stop()
        started = false
    }
}
