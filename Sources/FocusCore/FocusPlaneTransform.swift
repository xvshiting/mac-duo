import Foundation

public struct PlanePoint: Equatable {
    public let x: Double
    public let y: Double
}

/// Project the calibrated image onto the moving lid from a fixed virtual eye.
/// Coordinates are normalized, with the origin at the lower-left screen corner.
public struct FocusPlaneTransform {
    public static let defaultStrength = 0.28
    public let topLeft: PlanePoint
    public let topRight: PlanePoint
    public let bottomLeft = PlanePoint(x: 0, y: 0)
    public let bottomRight = PlanePoint(x: 1, y: 0)

    public init(angle: Double, focusAngle: Double, strength: Double = Self.defaultStrength) {
        guard angle.isFinite, focusAngle.isFinite, (25...180).contains(focusAngle), angle < focusAngle else {
            topLeft = PlanePoint(x: 0, y: 1)
            topRight = PlanePoint(x: 1, y: 1)
            return
        }
        // Eye measured from the hinge in the BASE frame: toward the user and up,
        // in screen heights. It does not move with either the lid or calibration.
        let eyeForward = 2.4, eyeUp = 0.8
        let focus = focusAngle * .pi / 180
        let delta = max(0, min(85, focusAngle - angle)) * .pi / 180
        let eyeHeight = eyeForward * cos(focus) + eyeUp * sin(focus)
        let eyeDistance = eyeForward * sin(focus) - eyeUp * cos(focus)
        // In the calibrated frame E=(0,h,d), a ray E→(x,y,0) meets
        // the physical lid at u=q*x/(q+y*sinδ), v=d*y/(q+y*sinδ).
        // The base-frame eye avoids the previous arbitrary screen-normal eye,
        // which exaggerated vertical compensation at ordinary opening angles.
        let q = max(eyeDistance * 0.6, eyeDistance * cos(delta) - eyeHeight * sin(delta))
        let denominator = q + sin(delta)
        let width = q / denominator
        // Near grazing angles exact compensation magnifies content. Bound the
        // vertical derivative at the hinge to 1, accepting drift there over stretch.
        let height = min(eyeDistance, q) / denominator
        // Blend the corners toward an upright plane while keeping the same hinge.
        // This perceptual adjustment deliberately relaxes exact ray compensation.
        // Since height <= width, blending both toward 1 preserves no-stretch bounds.
        let amount = strength.isFinite ? max(0, min(1, strength)) : Self.defaultStrength
        let adjustedWidth = 1 - amount * (1 - width)
        let adjustedHeight = 1 - amount * (1 - height)
        topLeft = PlanePoint(x: (1 - adjustedWidth) / 2, y: adjustedHeight)
        topRight = PlanePoint(x: (1 + adjustedWidth) / 2, y: adjustedHeight)
    }
}
