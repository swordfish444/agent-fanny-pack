import CoreGraphics
import Foundation

public enum ScreenPlacement {
    public static let defaultMargin: CGFloat = 8

    /// Horizontal origin that keeps a panel fully on screen.
    ///
    /// A menu bar popover is anchored to its status item, so an item near the edge of the
    /// display leaves the panel hanging past the boundary with its trailing column
    /// unreachable. This slides the panel back inside; the anchor arrow ends up off-centre
    /// from the status item, which is preferable to losing content.
    ///
    /// A panel wider than the screen pins to the leading edge rather than being pushed
    /// off the other side.
    public static func constrainedOriginX(
        panel: CGRect,
        within screen: CGRect,
        margin: CGFloat = defaultMargin
    ) -> CGFloat {
        var x = panel.origin.x
        if x + panel.width > screen.maxX - margin {
            x = screen.maxX - margin - panel.width
        }
        if x < screen.minX + margin {
            x = screen.minX + margin
        }
        return x
    }
}
