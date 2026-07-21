import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Static facts about this build — version, contact address, and a privacy-safe
/// diagnostics blurb the user can choose to attach to feedback. Centralised so
/// the marketing version and support address live in exactly one place.
enum AppInfo {
    /// Marketing version, e.g. "1.4".
    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }
    /// Build number, e.g. "34".
    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }
    /// "1.4 (34)".
    static var versionBuild: String { "\(version) (\(build))" }

    /// Where "Send feedback" is addressed. One line to change if the support
    /// mailbox ever moves.
    static let supportEmail = "feedback@prvital.app"

    /// A short, non-health diagnostics line the user can opt to include with
    /// feedback so a report can be triaged. Deliberately excludes any glucose or
    /// personal data — only app/device/OS facts.
    static var diagnostics: String {
        var lines = ["Prvital \(versionBuild)"]
        #if canImport(UIKit)
        let device = UIDevice.current
        lines.append("\(device.systemName) \(device.systemVersion)")
        lines.append("Model: \(deviceModelIdentifier)")
        #endif
        lines.append("Locale: \(Locale.current.identifier)")
        return lines.joined(separator: "\n")
    }

    /// The hardware identifier (e.g. "iPhone16,2"), more precise than the
    /// marketing name for triage.
    static var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }
}
