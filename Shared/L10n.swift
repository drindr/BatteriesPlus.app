import Foundation

enum L10n {
    private static let bundle: Bundle = {
        // batteryctl shares the enclosing app's localized resources when bundled.
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if app.pathExtension == "app", let bundle = Bundle(url: app) { return bundle }
        return .main
    }()

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
