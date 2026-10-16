import CoreGraphics
import Foundation

public enum Coordinates {
    public static func appKitRect(topLeft r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.origin.x, y: primaryHeight - (r.origin.y + r.height), width: r.width, height: r.height)
    }

    public static func topLeftRect(appKit r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.origin.x, y: primaryHeight - (r.origin.y + r.height), width: r.width, height: r.height)
    }
}
