import Foundation
import HighlightKit

enum AppLauncher {
    static let appPathEnvironmentKey = "HL_APP"
    private static let launchTimeout: TimeInterval = 5
    private static let pollInterval: UInt32 = 250_000

    static func candidatePaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths: [String] = []
        if let custom = ProcessInfo.processInfo.environment[appPathEnvironmentKey], !custom.isEmpty { paths.append(custom) }
        paths.append("\(home)/Applications/AgentHighlight.app")
        paths.append("/Applications/AgentHighlight.app")
        return paths
    }

    static func installedAppPath() -> String? {
        candidatePaths().first { FileManager.default.fileExists(atPath: $0) }
    }

    static func ensureRunning(client: Client) throws {
        if client.health() != nil { return }
        guard let path = installedAppPath() else {
            let searched = candidatePaths().joined(separator: ", ")
            throw ClientError.appUnavailable("AgentHighlight is not running and no app bundle was found (searched: \(searched)); set \(appPathEnvironmentKey) or run scripts/install.sh")
        }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = client.port == Defaults.port
            ? ["-a", path]
            : ["--env", "\(Defaults.portEnvironmentKey)=\(client.port)", "-a", path]
        try open.run()
        open.waitUntilExit()

        let deadline = Date().addingTimeInterval(launchTimeout)
        while Date() < deadline {
            usleep(pollInterval)
            if client.health() != nil { return }
        }
        throw ClientError.appUnavailable("launched \(path) but port \(client.port) did not answer within \(Int(launchTimeout))s")
    }
}
