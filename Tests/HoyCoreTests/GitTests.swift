import Testing
import Foundation
@testable import HoyCore

struct GitTests {
    private func makeWorkdir() throws -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @Test func init_createsDotGit() throws {
        let dir = try makeWorkdir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let git = Git(workdir: dir)
        try git.initIfNeeded()
        let dotGit = (dir as NSString).appendingPathComponent(".git")
        #expect(FileManager.default.fileExists(atPath: dotGit))
    }

    @Test func init_isIdempotent() throws {
        let dir = try makeWorkdir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let git = Git(workdir: dir)
        try git.initIfNeeded()
        try git.initIfNeeded()
    }

    @Test func commitAll_returnsSha() throws {
        let dir = try makeWorkdir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let git = Git(workdir: dir)
        try git.initIfNeeded()
        let file = (dir as NSString).appendingPathComponent("README.md")
        try "hello".write(toFile: file, atomically: true, encoding: .utf8)
        let sha = try git.commitAll(message: "first")
        #expect(sha.count == 40)
        #expect(try git.currentSha() == sha)
    }

    @Test func revert_createsRevertCommit() throws {
        let dir = try makeWorkdir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let git = Git(workdir: dir)
        try git.initIfNeeded()
        let file = (dir as NSString).appendingPathComponent("a.txt")
        try "v1".write(toFile: file, atomically: true, encoding: .utf8)
        let firstSha = try git.commitAll(message: "first")
        try "v2".write(toFile: file, atomically: true, encoding: .utf8)
        let secondSha = try git.commitAll(message: "second")
        let revertSha = try git.revert(sha: secondSha)
        #expect(revertSha != secondSha)
        #expect(revertSha != firstSha)
        let contents = try String(contentsOfFile: file, encoding: .utf8)
        #expect(contents == "v1")
    }

    @Test func runChecked_throwsOnFailure() throws {
        let dir = try makeWorkdir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let git = Git(workdir: dir)
        // git status without init はエラー
        #expect(throws: GitError.self) {
            try git.runChecked(["status"])
        }
    }
}
