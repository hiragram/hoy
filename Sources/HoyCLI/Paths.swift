import Foundation

public enum HoyPaths {
    /// 既定のワークスペース root: `$HOY_ROOT` か、未指定なら `~/.hoy/default`。
    public static func defaultRoot() -> String {
        if let env = ProcessInfo.processInfo.environment["HOY_ROOT"], !env.isEmpty {
            return env
        }
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/tmp"
        return (home as NSString).appendingPathComponent(".hoy/default")
    }

    public static func defaultSocketPath(root: String? = nil) -> String {
        if let env = ProcessInfo.processInfo.environment["HOY_SOCKET"], !env.isEmpty {
            return env
        }
        let r = root ?? defaultRoot()
        return (r as NSString).appendingPathComponent("socket")
    }
}
