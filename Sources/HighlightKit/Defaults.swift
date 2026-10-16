import Foundation

public enum Defaults {
    public static let port = 47831
    public static let duration: Double = 8
    public static let color = "#FF3B30"
    public static let dimAlpha: CGFloat = 0.45
    public static let padding: CGFloat = 6
    public static let cornerRadius: CGFloat = 8
    public static let version = "0.1.0"
    public static let portEnvironmentKey = "HL_PORT"

    public static func port(from environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
        guard let raw = environment[portEnvironmentKey], let value = Int(raw), (1...65535).contains(value) else {
            return port
        }
        return value
    }
}
