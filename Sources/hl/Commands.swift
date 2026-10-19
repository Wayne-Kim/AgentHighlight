import Foundation
import HighlightKit

enum ExitCode {
    static let success: Int32 = 0
    static let notFound: Int32 = 1
    static let appUnavailable: Int32 = 2
    static let usage: Int32 = 3
}

struct DoctorReport: Encodable {
    var ok: Bool
    var appRunning: Bool
    var trusted: Bool?
    var port: Int
    var version: String?
    var appPath: String?
    var launchError: String?
}

enum Commands {
    static let help = """
    hl - AgentHighlight CLI. 사람이 보는 화면 위에 영역을 가리킵니다. 출력은 JSON.

    hl text <문구> [--app 이름] [--title 정규식] [--role 역할] [--match contains|exact|regex]
                   [--index n] [--label 라벨] [--duration 초] [--color #RRGGBB] [--no-activate] [--no-dim]
    hl window --app 이름 [--title 정규식] [--label 라벨] ...
    hl rect <x> <y> <w> <h> [--label 라벨] ...
    hl figma <url> [--label 라벨] [--wait 초] [--app 브라우저]   링크를 열고 Figma 창을 가리킵니다
    hl json [<json> | -]                                        대상 여러 개를 한 번에 (HighlightRequest)
    hl steps [<json> | -]                                       대상을 한 단계씩 (targets[].note 로 설명)
    hl next | hl prev | hl status                               단계 넘기기, 지금 단계 확인
    hl find <문구> [--app 이름] ...                             그리지 않고 좌표만
    hl windows [--app 이름] [--title 정규식]
    hl clear
    hl doctor                                                   앱 실행 여부, 접근성 권한, 포트

    좌표는 주 모니터 왼쪽 위 원점. 종료 코드: 0 성공, 1 대상 못 찾음, 2 앱 연결 실패, 3 인자 오류.
    환경 변수: HL_PORT(기본 47831), HL_APP(앱 번들 경로).
    """

    static func run(_ argv: [String]) -> Int32 {
        let args = Arguments(argv)
        guard let command = args.positionals.first, !args.has("help") else {
            print(help)
            return args.has("help") ? ExitCode.success : ExitCode.usage
        }
        let client = Client(port: args.int("port") ?? Defaults.port())

        switch command {
        case "help":
            print(help)
            return ExitCode.success
        case "doctor":
            return doctor(client)
        case "clear":
            return withApp(client) { try client.post("/clear", OKBody()) }
        case "windows":
            return withApp(client) {
                var query: [String: String] = [:]
                if let app = args.option("app") { query["app"] = app }
                if let title = args.option("title") { query["title"] = title }
                return try client.get("/windows", query: query)
            }
        case "text", "find":
            return highlightText(args, client: client, path: command == "find" ? "/find" : "/highlight")
        case "window":
            let target = Target(kind: .window, app: args.option("app"), title: args.option("title"), label: args.option("label"))
            return highlight(makeRequest(args, targets: [target]), client: client)
        case "rect":
            return highlightRect(args, client: client)
        case "figma":
            return figma(args, client: client)
        case "json":
            return json(args, client: client, path: "/highlight")
        case "steps":
            return json(args, client: client, path: "/steps")
        case "next":
            return withApp(client) { try client.post("/steps/next", OKBody()) }
        case "prev":
            return withApp(client) { try client.post("/steps/prev", OKBody()) }
        case "status":
            return withApp(client) { try client.get("/steps") }
        default:
            return Output.fail("unknown command: \(command)\n\(help)", code: ExitCode.usage)
        }
    }

    private struct OKBody: Encodable {}

    private static func doctor(_ client: Client) -> Int32 {
        var report = DoctorReport(ok: false, appRunning: false, port: client.port, appPath: AppLauncher.installedAppPath())
        do {
            try AppLauncher.ensureRunning(client: client)
        } catch let error as ClientError {
            report.launchError = error.message
        } catch {
            report.launchError = error.localizedDescription
        }
        if let health = client.health() {
            report.appRunning = true
            report.trusted = health.trusted
            report.version = health.version
            report.ok = health.trusted
        }
        Output.print(report)
        return report.appRunning ? ExitCode.success : ExitCode.appUnavailable
    }

    private static func highlightText(_ args: Arguments, client: Client, path: String) -> Int32 {
        guard args.positionals.count >= 2 else {
            return Output.fail("usage: hl \(args.positionals[0]) <문구> [--app 이름] ...", code: ExitCode.usage)
        }
        let query = args.positionals.dropFirst().joined(separator: " ")
        if let index = args.int("index"), index < 0 {
            return Output.fail("--index must be >= 0", code: ExitCode.usage)
        }
        var mode: MatchMode?
        if let raw = args.option("match") {
            guard let parsed = MatchMode(rawValue: raw) else {
                return Output.fail("--match must be contains, exact or regex", code: ExitCode.usage)
            }
            mode = parsed
        }
        let target = Target(
            kind: .element,
            app: args.option("app"),
            title: args.option("title"),
            text: query,
            role: args.option("role"),
            match: mode,
            index: args.int("index"),
            label: args.option("label")
        )
        return highlight(makeRequest(args, targets: [target]), client: client, path: path)
    }

    private static func highlightRect(_ args: Arguments, client: Client) -> Int32 {
        let numbers = args.positionals.dropFirst().compactMap(Double.init)
        guard numbers.count == 4 else {
            return Output.fail("usage: hl rect <x> <y> <w> <h> [--label 라벨]", code: ExitCode.usage)
        }
        let rect = Rect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        let target = Target(kind: .rect, rect: rect, label: args.option("label"))
        return highlight(makeRequest(args, targets: [target]), client: client)
    }

    private static func figma(_ args: Arguments, client: Client) -> Int32 {
        guard args.positionals.count >= 2, let url = URL(string: args.positionals[1]), url.scheme != nil else {
            return Output.fail("usage: hl figma <url> [--label 라벨] [--wait 초]", code: ExitCode.usage)
        }
        let browser = args.option("app") ?? "Google Chrome"
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = args.option("app").map { ["-a", $0, url.absoluteString] } ?? [url.absoluteString]
        do {
            try open.run()
            open.waitUntilExit()
        } catch {
            return Output.fail("cannot open url: \(error.localizedDescription)", code: ExitCode.appUnavailable)
        }
        let title = args.option("title") ?? #"Figma(\s*-|$)"#
        let wait = args.double("wait") ?? 10
        guard waitForWindow(app: browser, title: title, seconds: wait, client: client) else {
            return Output.fail(
                "no \(browser) window titled /\(title)/ appeared within \(Int(wait))s; the link may have opened in another browser - pass --app <browser> or --title <regex>",
                code: ExitCode.notFound
            )
        }
        let target = Target(
            kind: .window,
            app: browser,
            title: title,
            label: args.option("label") ?? "Figma: 선택된 노드(파란 테두리)를 보세요"
        )
        var request = makeRequest(args, targets: [target])
        request.duration = request.duration ?? 15
        return highlight(request, client: client)
    }

    private static func waitForWindow(app: String, title: String, seconds: Double, client: Client) -> Bool {
        guard (try? AppLauncher.ensureRunning(client: client)) != nil else { return false }
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if let (status, data) = try? client.get("/windows", query: ["app": app, "title": title]),
               status == 200,
               let response = try? JSONDecoder().decode(WindowsResponse.self, from: data),
               !response.windows.isEmpty {
                return true
            }
            usleep(500_000)
        } while Date() < deadline
        return false
    }

    private static func json(_ args: Arguments, client: Client, path: String) -> Int32 {
        let source = args.positionals.count >= 2 ? args.positionals[1] : "-"
        let data: Data
        if source == "-" {
            data = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            data = Data(source.utf8)
        }
        guard (try? JSONDecoder().decode(HighlightRequest.self, from: data)) != nil else {
            return Output.fail("input is not a valid HighlightRequest JSON", code: ExitCode.usage)
        }
        return withApp(client, successCode: { $0.ok ? ExitCode.success : ExitCode.notFound }) {
            try client.postRaw(path, data)
        }
    }

    private static func makeRequest(_ args: Arguments, targets: [Target]) -> HighlightRequest {
        HighlightRequest(
            targets: targets,
            duration: args.double("duration"),
            activate: args.has("no-activate") ? false : nil,
            style: Style(color: args.option("color"), dim: args.has("no-dim") ? false : nil)
        )
    }

    private static func highlight(_ request: HighlightRequest, client: Client, path: String = "/highlight") -> Int32 {
        withApp(client, successCode: { $0.ok ? ExitCode.success : ExitCode.notFound }) {
            try client.post(path, request)
        }
    }

    private static func withApp(
        _ client: Client,
        successCode: (HighlightResponse) -> Int32 = { _ in ExitCode.success },
        _ call: () throws -> (Int, Data)
    ) -> Int32 {
        do {
            try AppLauncher.ensureRunning(client: client)
            let (status, data) = try call()
            Output.printRaw(data)
            guard status == 200 else { return ExitCode.usage }
            if let response = try? JSONDecoder().decode(HighlightResponse.self, from: data) {
                return successCode(response)
            }
            return ExitCode.success
        } catch let error as ClientError {
            return Output.fail(error.message, code: ExitCode.appUnavailable)
        } catch {
            return Output.fail(error.localizedDescription, code: ExitCode.appUnavailable)
        }
    }
}
