import Foundation

enum DisplayMode: UInt32, CaseIterable {
    case scalar = 0
    case complexAbs = 1
    case complexPhase = 2
    case complexReal = 3
    case complexImag = 4
    case complexIntensity = 5

    var label: String {
        switch self {
        case .scalar:
            "scalar"
        case .complexAbs:
            "abs"
        case .complexPhase:
            "phase"
        case .complexReal:
            "real"
        case .complexImag:
            "imag"
        case .complexIntensity:
            "intensity"
        }
    }

    var menuLabel: String {
        switch self {
        case .scalar:
            "Scalar"
        case .complexAbs:
            "Abs"
        case .complexPhase:
            "Phase"
        case .complexReal:
            "Real"
        case .complexImag:
            "Imag"
        case .complexIntensity:
            "Intensity"
        }
    }
}
