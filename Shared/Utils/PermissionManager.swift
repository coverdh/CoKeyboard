import AVFoundation
import UIKit

enum MicrophonePermission {
    case granted
    case denied
    case undetermined

    static var current: MicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }

    static func request() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

enum PermissionURLScheme {
    static let scheme = "cokeyboard"
    static let requestMicPermission = "cokeyboard://request-mic-permission"

    static func openMainAppForPermission(from viewController: UIViewController?) {
        guard let url = URL(string: requestMicPermission) else { return }

        // In keyboard extension, we need to use the parent app's openURL
        if let vc = viewController as? UIInputViewController {
            // Use the shared application to open URL
            let selector = NSSelectorFromString("openURL:")
            var responder: UIResponder? = vc
            while let r = responder {
                if r.responds(to: selector) {
                    r.perform(selector, with: url)
                    return
                }
                responder = r.next
            }
        }
    }
}
