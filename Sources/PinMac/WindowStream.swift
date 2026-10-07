import AppKit
import ScreenCaptureKit

enum PinError: LocalizedError {
    case windowNotFound

    var errorDescription: String? {
        switch self {
        case .windowNotFound: "PinMac couldn't find that window. Make sure Screen Recording is allowed for PinMac."
        }
    }
}

/// Streams live frames of a single window using ScreenCaptureKit. The window is
/// captured on its own, so frames stay correct even while it's covered by others.
final class WindowStream: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let onFrame: @MainActor (IOSurface) -> Void
    private let onStop: @MainActor () -> Void

    init(onFrame: @escaping @MainActor (IOSurface) -> Void, onStop: @escaping @MainActor () -> Void) {
        self.onFrame = onFrame
        self.onStop = onStop
    }

    /// `sourceRect` limits capture to part of the window, in window points from its top-left.
    func start(windowID: CGWindowID, size: CGSize, scale: CGFloat, sourceRect: CGRect? = nil) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw PinError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = Self.configuration(size: size, scale: scale, sourceRect: sourceRect)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        self.stream = stream
    }

    func resize(to size: CGSize, scale: CGFloat, sourceRect: CGRect? = nil) {
        stream?.updateConfiguration(Self.configuration(size: size, scale: scale, sourceRect: sourceRect)) { _ in }
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
    }

    private static func configuration(size: CGSize, scale: CGFloat, sourceRect: CGRect?) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        if let sourceRect { config.sourceRect = sourceRect }
        config.width = max(1, Int(size.width * scale))
        config.height = max(1, Int(size.height * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 3
        config.showsCursor = false
        return config
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        // The sample handler queue is .main, so this is already the main thread.
        MainActor.assumeIsolated { onFrame(surface) }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onStop() }
    }
}
