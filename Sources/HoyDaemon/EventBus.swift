import Foundation

/// EventBus: daemon 内で発生したイベントを購読中の接続に push する。
/// MVP の最小実装 — スレッドセーフな subscriber リストとブロードキャスト。
public final class EventBus: @unchecked Sendable {
    public typealias Subscriber = (_ event: String, _ payload: Data) -> Void

    private let lock = NSLock()
    private var subscribers: [(id: Int, filter: Set<String>?, callback: Subscriber)] = []
    private var nextId = 0

    public init() {}

    /// subscribe する。`filter` が nil なら全イベント、空集合だと何も購読しない (エッジケース)。
    /// 戻り値は解除に使う ID。
    @discardableResult
    public func subscribe(filter: Set<String>?, callback: @escaping Subscriber) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let id = nextId
        nextId += 1
        subscribers.append((id: id, filter: filter, callback: callback))
        return id
    }

    public func unsubscribe(id: Int) {
        lock.lock()
        defer { lock.unlock() }
        subscribers.removeAll { $0.id == id }
    }

    public func publish(event: String, payload: Data) {
        let snapshot: [(Int, Set<String>?, Subscriber)] = {
            lock.lock(); defer { lock.unlock() }
            return subscribers.map { ($0.id, $0.filter, $0.callback) }
        }()
        for (_, filter, cb) in snapshot {
            if let filter, !filter.contains(event) { continue }
            cb(event, payload)
        }
    }
}
