import SwiftUI
import UIKit

/// Where an input sits inside a block of inputs collapsed by
/// ``GopayCardFormTheme/inputBorderCollapse``.
///
/// The position decides which of the field's edges it draws — a line shared with a neighbour is
/// drawn by one field only, so the block reads as a single box rather than a grid of boxes — and
/// which of its corners the border radius rounds, which is only ever a corner of the whole block.
///
/// Mirrors the Android `CollapsedBorderPosition`, so both platforms hand the same edge to the same
/// field.
enum GopayCollapsedInputPosition {
    /// Full-width field on top of the block: the card number.
    case top
    /// Leading field of the bottom row: the expiration.
    case bottomStart
    /// Trailing field of the bottom row: the CVV.
    case bottomEnd
}

/// Edges and corners a collapsed field draws, resolved to physical sides for the draw phase.
struct GopayCollapsedBorderEdges: Equatable {
    var drawTop: Bool
    var drawBottom: Bool
    var drawLeft: Bool
    var drawRight: Bool
    var roundTopLeft: Bool
    var roundTopRight: Bool
    var roundBottomRight: Bool
    var roundBottomLeft: Bool

    /// The rounded corners as a `UIRectCorner`, for clipping the field's background to them.
    var corners: UIRectCorner {
        var corners: UIRectCorner = []
        if roundTopLeft { corners.insert(.topLeft) }
        if roundTopRight { corners.insert(.topRight) }
        if roundBottomRight { corners.insert(.bottomRight) }
        if roundBottomLeft { corners.insert(.bottomLeft) }
        return corners
    }
}

/// Resolves `position` into physical edges, mirroring leading and trailing in a right-to-left
/// layout. The result is physical and final: the form draws it in a fixed left-to-right environment,
/// so SwiftUI's own mirroring of shapes cannot flip it a second time.
///
/// A shared line is left to one field only where the two fields actually meet. `rowsTouch` says the
/// card number sits flush on the bottom row, `bottomRowTouches` says the expiration sits flush
/// against the CVV. Where a gap separates them, both fields draw a full frame instead, the way the
/// web form does — a field floating on its own is never missing a side.
func gopayCollapsedBorderEdges(
    position: GopayCollapsedInputPosition,
    layoutDirection: LayoutDirection,
    rowsTouch: Bool,
    bottomRowTouches: Bool
) -> GopayCollapsedBorderEdges {
    // Resolved in leading/trailing terms first, then mapped to physical sides.
    let outerTop: Bool, outerBottom: Bool, outerLeading: Bool, outerTrailing: Bool
    let drawTop: Bool, drawBottom: Bool, drawLeading: Bool, drawTrailing: Bool

    switch position {
    case .top:
        // Owns the line it shares with the row below.
        outerTop = true
        outerBottom = !rowsTouch
        outerLeading = true
        outerTrailing = true
        drawTop = true
        drawBottom = true
        drawLeading = true
        drawTrailing = true

    case .bottomStart:
        // Owns the line it shares with the trailing field.
        outerTop = !rowsTouch
        outerBottom = true
        outerLeading = true
        outerTrailing = !bottomRowTouches
        drawTop = !rowsTouch
        drawBottom = true
        drawLeading = true
        drawTrailing = true

    case .bottomEnd:
        outerTop = !rowsTouch
        outerBottom = true
        outerLeading = !bottomRowTouches
        outerTrailing = true
        drawTop = !rowsTouch
        drawBottom = true
        drawLeading = !bottomRowTouches
        drawTrailing = true
    }

    // A corner is rounded where two outer sides of the block meet.
    let roundTopLeading = outerTop && outerLeading
    let roundTopTrailing = outerTop && outerTrailing
    let roundBottomTrailing = outerBottom && outerTrailing
    let roundBottomLeading = outerBottom && outerLeading

    let leftIsLeading = layoutDirection == .leftToRight
    return GopayCollapsedBorderEdges(
        drawTop: drawTop,
        drawBottom: drawBottom,
        drawLeft: leftIsLeading ? drawLeading : drawTrailing,
        drawRight: leftIsLeading ? drawTrailing : drawLeading,
        roundTopLeft: leftIsLeading ? roundTopLeading : roundTopTrailing,
        roundTopRight: leftIsLeading ? roundTopTrailing : roundTopLeading,
        roundBottomRight: leftIsLeading ? roundBottomTrailing : roundBottomLeading,
        roundBottomLeft: leftIsLeading ? roundBottomLeading : roundBottomTrailing
    )
}

/// A rectangle that rounds only the given corners. Used to clip the background of an input inside
/// a collapsed block, where only the outside of the block is rounded.
struct GopayPartiallyRoundedRectangle: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radii = GopayCornerRadii(radius: radius, corners: corners, in: rect)

        path.move(to: CGPoint(x: rect.minX + radii.topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radii.topRight, y: rect.minY))
        radii.addTopRightArc(to: &path, in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radii.bottomRight))
        radii.addBottomRightArc(to: &path, in: rect)
        path.addLine(to: CGPoint(x: rect.minX + radii.bottomLeft, y: rect.maxY))
        radii.addBottomLeftArc(to: &path, in: rect)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radii.topLeft))
        radii.addTopLeftArc(to: &path, in: rect)
        path.closeSubpath()
        return path
    }
}

/// The outline of an input inside a collapsed block: only the sides that input draws, with a corner
/// arc wherever two drawn sides meet on a rounded corner.
///
/// The stroke is centred half a line width inside the input, so the whole line shows and a
/// collapsed block and a boxed field of the same theme draw lines of the same weight.
struct GopayCollapsedInputBorder: Shape {
    var radius: CGFloat
    var lineWidth: CGFloat
    var edges: GopayCollapsedBorderEdges

    /// The weight of the drawn line. A collapsed cell is not clipped, so the whole line shows and
    /// the value is the one the theme asked for, as on Android and on the web.
    var strokeWidth: CGFloat { lineWidth }

    /// The outline stroked at its own weight in `color`.
    func stroked(_ color: Color) -> some View {
        stroke(color, lineWidth: strokeWidth)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Centered on the inner half of the line, and never past the middle of the cell: a line
        // thicker than the cell would otherwise inset the rect away to nothing and every point of
        // the path would come out non-finite.
        let inset = min(strokeWidth / 2, min(rect.width, rect.height) / 2)
        let rect = rect.insetBy(dx: inset, dy: inset)
        let radii = GopayCornerRadii(radius: radius - inset, corners: edges.corners, in: rect)

        if edges.drawTop {
            path.move(to: CGPoint(x: rect.minX + radii.topLeft, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radii.topRight, y: rect.minY))
        }
        if edges.drawTop, edges.drawRight {
            radii.addTopRightArc(to: &path, in: rect)
        }
        if edges.drawRight {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY + radii.topRight))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radii.bottomRight))
        }
        if edges.drawRight, edges.drawBottom {
            radii.addBottomRightArc(to: &path, in: rect)
        }
        if edges.drawBottom {
            path.move(to: CGPoint(x: rect.maxX - radii.bottomRight, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + radii.bottomLeft, y: rect.maxY))
        }
        if edges.drawBottom, edges.drawLeft {
            radii.addBottomLeftArc(to: &path, in: rect)
        }
        if edges.drawLeft {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - radii.bottomLeft))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radii.topLeft))
        }
        if edges.drawLeft, edges.drawTop {
            radii.addTopLeftArc(to: &path, in: rect)
        }
        return path
    }
}

/// The lines a collapsed input in a state paints over its neighbours: for every shared side the
/// input does not draw itself, the neighbour's half of that line, which lies just outside the
/// input's own bounds.
///
/// Together with the input's own outline in the same color the seam then shows one line in the
/// state color, the way the web recolors the single shared border of a focused or invalid cell. The
/// form draws it unclipped and above the neighbours. Where two covered sides meet, the band extends
/// around the corner so the corner square is repainted as well.
struct GopayCollapsedSeamCover: Shape {
    var lineWidth: CGFloat
    var edges: GopayCollapsedBorderEdges

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // The neighbour draws the shared line inside itself, at the weight the theme asks for, so
        // repainting it takes a band of the whole width just outside this cell.
        let band = lineWidth
        // A covered side extends past a corner only towards another covered side.
        let leftReach = edges.drawLeft ? 0 : band
        let rightReach = edges.drawRight ? 0 : band
        let topReach = edges.drawTop ? 0 : band
        let bottomReach = edges.drawBottom ? 0 : band

        if !edges.drawTop {
            path.addRect(CGRect(
                x: rect.minX - leftReach, y: rect.minY - band,
                width: rect.width + leftReach + rightReach, height: band
            ))
        }
        if !edges.drawBottom {
            path.addRect(CGRect(
                x: rect.minX - leftReach, y: rect.maxY,
                width: rect.width + leftReach + rightReach, height: band
            ))
        }
        if !edges.drawLeft {
            path.addRect(CGRect(
                x: rect.minX - band, y: rect.minY - topReach,
                width: band, height: rect.height + topReach + bottomReach
            ))
        }
        if !edges.drawRight {
            path.addRect(CGRect(
                x: rect.maxX, y: rect.minY - topReach,
                width: band, height: rect.height + topReach + bottomReach
            ))
        }
        return path
    }
}

/// The per-corner radius of a partially rounded rectangle, capped so opposite corners cannot
/// overlap on a short edge and so a hostile value cannot invert a side.
struct GopayCornerRadii {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomRight: CGFloat
    let bottomLeft: CGFloat

    init(radius: CGFloat, corners: UIRectCorner, in rect: CGRect) {
        let capped = max(0, min(radius, min(rect.width, rect.height) / 2))
        let value: (UIRectCorner) -> CGFloat = { corners.contains($0) ? capped : 0 }
        topLeft = value(.topLeft)
        topRight = value(.topRight)
        bottomRight = value(.bottomRight)
        bottomLeft = value(.bottomLeft)
    }

    func addTopRightArc(to path: inout Path, in rect: CGRect) {
        guard topRight > 0 else { return }
        path.addArc(
            center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
            radius: topRight, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
    }

    func addBottomRightArc(to path: inout Path, in rect: CGRect) {
        guard bottomRight > 0 else { return }
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
            radius: bottomRight, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
    }

    func addBottomLeftArc(to path: inout Path, in rect: CGRect) {
        guard bottomLeft > 0 else { return }
        path.addArc(
            center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
            radius: bottomLeft, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
    }

    func addTopLeftArc(to path: inout Path, in rect: CGRect) {
        guard topLeft > 0 else { return }
        path.addArc(
            center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
            radius: topLeft, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
    }
}
