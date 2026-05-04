import Foundation

// ADR 0035: バックアップ・リストア。MVP は state.db と repo/ をディレクトリコピー。

public enum BackupError: Error, CustomStringConvertible {
    case copyFailed(String)
    case sourceMissing(String)

    public var description: String {
        switch self {
        case .copyFailed(let m): return "backup copy failed: \(m)"
        case .sourceMissing(let p): return "source missing: \(p)"
        }
    }
}

public final class Backup {
    private let workspace: Workspace

    public init(workspace: Workspace) {
        self.workspace = workspace
    }

    /// `<destination>/<timestamp>/` 配下に state.db と repo をコピー。
    public func snapshot(to destination: String, now: Date = Date()) throws -> String {
        let stamp = ISO8601DateFormatter().string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        let dir = (destination as NSString).appendingPathComponent(stamp)
        let fm = FileManager.default
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let dbSrc = workspace.storage.path
        let dbDst = (dir as NSString).appendingPathComponent("state.db")
        guard fm.fileExists(atPath: dbSrc) else {
            throw BackupError.sourceMissing(dbSrc)
        }
        try fm.copyItem(atPath: dbSrc, toPath: dbDst)

        let repoSrc = (workspace.root as NSString).appendingPathComponent("repo")
        let repoDst = (dir as NSString).appendingPathComponent("repo")
        if fm.fileExists(atPath: repoSrc) {
            try fm.copyItem(atPath: repoSrc, toPath: repoDst)
        }

        return dir
    }
}
