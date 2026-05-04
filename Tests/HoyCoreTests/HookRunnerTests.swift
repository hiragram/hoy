import Testing
import Foundation
@testable import HoyCore

struct HookRunnerTests {
    private let actor = PrincipalRef(id: "agent-1", kind: .agent)

    @Test func taskCompleted_invokesHookWithPayload() throws {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-hook-\(UUID().uuidString)")
        let ws = try Workspace.open(at: root)

        let hooks = (root as NSString).appendingPathComponent("hooks")
        try FileManager.default.createDirectory(atPath: hooks, withIntermediateDirectories: true)
        let marker = (root as NSString).appendingPathComponent("marker.json")
        let script = """
        #!/bin/sh
        cat > \(marker)
        """
        let scriptPath = (hooks as NSString).appendingPathComponent("task.completed.sh")
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        chmod(scriptPath, 0o755)

        let svc = TaskService(workspace: ws)
        let task = HoyTask.create(intentId: "i", title: "x", createdBy: actor)
        try ws.tasks.save(task)
        _ = try svc.complete(task: task, by: actor)

        // hook は非同期起動なので最大 1 秒待つ
        var found = false
        for _ in 0..<20 {
            if FileManager.default.fileExists(atPath: marker) {
                found = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        #expect(found)
        if found {
            let contents = try String(contentsOfFile: marker, encoding: .utf8)
            #expect(contents.contains("\"event\":\"task.completed\""))
            #expect(contents.contains("\"taskId\":\"\(task.id)\""))
        }
    }

    @Test func missingHook_doesNothing() throws {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("hoy-hook-\(UUID().uuidString)")
        let runner = HookRunner(workspaceRoot: root)
        runner.fire(event: "no.such.event", payload: ["x": "y"])
    }
}
