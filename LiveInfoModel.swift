import Foundation
import AppKit

@Observable
class LiveInfoModel {
    var mouseX: Int = 0
    var mouseY: Int = 0
    var frontmostApp: String = "Unknown"
    var screenRecordingGranted: Bool = false
    var accessibilityGranted: Bool = false
    var screenCount: Int = 0
    var screenDescriptions: [String] = []
    var buildTimestamp: String = BUILD_TIMESTAMP
}
