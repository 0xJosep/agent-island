import CoreGraphics
import Foundation

final class ScreenShare: ObservableObject {
    static let shared = ScreenShare()

    @Published var isShared = false

    private var timer: Timer?

    private init() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    private func check() {
        let shared = Self.sessionScreenIsShared()
        guard shared != isShared else { return }
        isShared = shared
        EventLog.shared.log("event", shared ? "screen share detected" : "screen share ended")
    }

    private static func sessionScreenIsShared() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsShared"] as? NSNumber)?.boolValue ?? false
    }
}
