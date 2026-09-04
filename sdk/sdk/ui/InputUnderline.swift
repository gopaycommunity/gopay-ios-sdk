import SwiftUI

/// The bottom line of an input drawn in the ``GopayCardFormBorderStyle/underline`` style.
///
/// The line runs along the bottom edge and climbs the two bottom corners on their arcs, so its ends
/// are never cut off by the corner clip. The path is inset by half the line width, which keeps the
/// whole stroke inside the input.
///
/// This is close to a CSS `border-bottom` under a `border-radius` but not identical: a browser
/// hands the corner over to the side border along the diagonal, so with no side border the line
/// tapers to a point at 45 degrees. Here it keeps its full width all the way around the corner.
struct GopayInputUnderline: Shape {
    var radius: CGFloat
    var lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = lineWidth / 2
        // An oversized radius is capped the way a browser caps border-radius, and a radius smaller
        // than the inset leaves no arc to draw.
        let corner = max(0, min(radius, min(rect.width, rect.height) / 2))
        let arc = max(0, corner - inset)
        let bottom = rect.maxY - inset

        if arc > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + corner, y: rect.maxY - corner),
                radius: arc, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true
            )
        } else {
            path.move(to: CGPoint(x: rect.minX + corner, y: bottom))
        }
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: bottom))
        if arc > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - corner, y: rect.maxY - corner),
                radius: arc, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true
            )
        }
        return path
    }
}
