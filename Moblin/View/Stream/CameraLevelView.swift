import CoreMotion
import SwiftUI

struct CameraLevelView: View {
    @ObservedObject var cameraLevel: CameraLevel

    var body: some View {
        Canvas { context, size in
            guard let angle = cameraLevel.angle else {
                return
            }
            let y = size.height / 2
            let xLeft = size.width / 3
            let xRight = size.width * 2 / 3
            let halfGap = 2.5
            let shortLine = 25.0
            var path = Path()
            let color: Color
            if abs(angle) < 0.01 {
                path.move(to: CGPoint(x: xLeft - shortLine - halfGap, y: y))
                path.addLine(to: CGPoint(x: xRight + shortLine + halfGap, y: y))
                color = .yellow
            } else {
                // Left
                path.move(to: CGPoint(x: xLeft - shortLine - halfGap, y: y))
                path.addLine(to: CGPoint(x: xLeft - halfGap, y: y))
                // Right
                path.move(to: CGPoint(x: xRight + halfGap, y: y))
                path.addLine(to: CGPoint(x: xRight + halfGap + shortLine, y: y))
                // Middle
                if abs(angle) < 0.5 {
                    let longLine = xRight - xLeft - 2 * halfGap
                    let xLine = cos(angle) * longLine / 2
                    let yLine = sin(angle) * longLine / 2
                    path.move(to: CGPoint(x: size.width / 2 - xLine, y: y - yLine))
                    path.addLine(to: CGPoint(x: size.width / 2 + xLine, y: y + yLine))
                }
                color = .white
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
