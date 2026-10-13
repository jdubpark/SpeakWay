import Foundation
import CoreGraphics

/// Capture and results share a bottom-center anchor within the display's usable area.
public enum PopoverLayout: Equatable {
    case launcher, continuation, capture, result(VoiceMode), failure

    public var preferredSize: CGSize {
        switch self {
        case .launcher: return CGSize(width: 380, height: 330)
        case .continuation: return CGSize(width: 420, height: 490)
        case .capture: return CGSize(width: 352, height: 68)
        case .result(.dictate): return CGSize(width: 520, height: 340)
        case .result(.translate): return CGSize(width: 520, height: 420)
        case .result(.ask): return CGSize(width: 560, height: 560)
        case .failure: return CGSize(width: 460, height: 300)
        }
    }

    public func frame(in visibleFrame: CGRect) -> CGRect {
        let margin = min(16, max(0, min(visibleFrame.width, visibleFrame.height) / 4))
        let bottom = min(42, max(margin, visibleFrame.height / 8))
        let size = CGSize(width: min(preferredSize.width, max(0, visibleFrame.width - margin * 2)),
                          height: min(preferredSize.height, max(0, visibleFrame.height - bottom - margin)))
        return CGRect(x: visibleFrame.midX - size.width / 2, y: visibleFrame.minY + bottom,
                      width: size.width, height: size.height)
    }
}
