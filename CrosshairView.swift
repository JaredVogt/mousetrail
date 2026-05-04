import Cocoa
import QuartzCore

/// Renders horizontal + vertical crosshair lines that span the view bounds at
/// the cursor's view-local position. Lives in a per-screen full-screen overlay
/// — separate from the trail so the trail window can be small and mobile.
class CrosshairView: NSView {
    private let verticalLayer = CAShapeLayer()
    private let horizontalLayer = CAShapeLayer()
    private var lastPoint: NSPoint?

    var isCrosshairVisible = false {
        didSet {
            verticalLayer.isHidden = !isCrosshairVisible
            horizontalLayer.isHidden = !isCrosshairVisible
            if !isCrosshairVisible { lastPoint = nil }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false

        verticalLayer.fillColor = nil
        verticalLayer.frame = bounds
        verticalLayer.isHidden = true

        horizontalLayer.fillColor = nil
        horizontalLayer.frame = bounds
        horizontalLayer.isHidden = true

        applyStyle(color: NSColor.white.withAlphaComponent(0.3), lineWidth: 1.0)

        layer?.addSublayer(verticalLayer)
        layer?.addSublayer(horizontalLayer)
    }

    override var frame: NSRect {
        didSet {
            verticalLayer.frame = bounds
            horizontalLayer.frame = bounds
        }
    }

    /// Update crosshair position. `viewPoint` is in view-local coordinates.
    func update(at viewPoint: NSPoint) {
        guard isCrosshairVisible else { return }

        if let last = lastPoint,
           abs(last.x - viewPoint.x) < 0.5 && abs(last.y - viewPoint.y) < 0.5 {
            return
        }
        lastPoint = viewPoint

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let verticalPath = CGMutablePath()
        verticalPath.move(to: CGPoint(x: viewPoint.x, y: 0))
        verticalPath.addLine(to: CGPoint(x: viewPoint.x, y: bounds.height))
        verticalLayer.path = verticalPath

        let horizontalPath = CGMutablePath()
        horizontalPath.move(to: CGPoint(x: 0, y: viewPoint.y))
        horizontalPath.addLine(to: CGPoint(x: bounds.width, y: viewPoint.y))
        horizontalLayer.path = horizontalPath

        CATransaction.commit()
    }

    func applyStyle(color: NSColor, lineWidth: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        verticalLayer.strokeColor = color.cgColor
        verticalLayer.lineWidth = lineWidth
        horizontalLayer.strokeColor = color.cgColor
        horizontalLayer.lineWidth = lineWidth
        CATransaction.commit()
    }

    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        verticalLayer.path = nil
        horizontalLayer.path = nil
        CATransaction.commit()
        lastPoint = nil
    }
}
