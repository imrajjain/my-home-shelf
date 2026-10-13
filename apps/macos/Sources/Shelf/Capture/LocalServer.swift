import Foundation
import Network
import ShelfCore

/// Serves `LocalAPI` on 127.0.0.1 so the browser extension can add things
/// silently — no URL-scheme prompts, no window switching.
final class LocalServer {
    static let shared = LocalServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "shelf.local-api")
    private(set) var isRunning = false

    func start(port: UInt16 = LocalAPI.defaultPort) {
        guard listener == nil, let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: params, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.isRunning = true
                case .failed, .cancelled: self?.isRunning = false
                default: break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("Shelf: local API failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Connections

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
        // Don't let a stuck client hold a socket forever.
        queue.asyncAfter(deadline: .now() + 10) { connection.cancel() }
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch LocalAPI.parse(buffer) {
            case .complete(let request):
                Task { @MainActor in
                    let response = Self.respond(to: request)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            case .needMoreData where !isComplete && error == nil:
                self.receive(on: connection, buffer: buffer)
            default:
                connection.send(content: LocalAPI.response(status: 400, json: ["ok": false, "error": "bad request"]),
                                completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    @MainActor
    private static func respond(to request: LocalAPI.Request) -> Data {
        // Browsers send an Origin header from web pages; we only serve
        // extensions (whose service workers aren't subject to CORS).
        if let origin = request.headers["origin"], !Self.isExtensionOrigin(origin) {
            return LocalAPI.response(status: 401, json: ["ok": false, "error": "origin not allowed"])
        }
        guard LocalAPI.tokensMatch(request.headers[LocalAPI.tokenHeader], AppSettings.apiToken) else {
            return LocalAPI.response(status: 401, json: ["ok": false, "error": "pair the extension in Shelf → Settings"])
        }

        switch (request.method, request.path) {
        case ("GET", "/v1/ping"):
            return LocalAPI.response(status: 200, json: ["ok": true, "app": "Shelf", "version": "0.1"])
        case ("POST", "/v1/items"):
            let decoder = JSONDecoder()
            guard let capture = try? decoder.decode(CaptureRequest.self, from: request.body), !capture.isEmpty else {
                return LocalAPI.response(status: 400, json: ["ok": false, "error": "expected {url, title, …}"])
            }
            guard let item = CaptureCoordinator.shared.add(capture) else {
                return LocalAPI.response(status: 400, json: ["ok": false, "error": "nothing to add"])
            }
            return LocalAPI.response(status: 201, json: [
                "ok": true, "id": item.id.uuidString, "kind": item.kindRaw, "title": item.title,
            ])
        case (_, "/v1/ping"), (_, "/v1/items"):
            return LocalAPI.response(status: 405, json: ["ok": false, "error": "method not allowed"])
        default:
            return LocalAPI.response(status: 404, json: ["ok": false, "error": "not found"])
        }
    }

    private static func isExtensionOrigin(_ origin: String) -> Bool {
        ["chrome-extension://", "moz-extension://", "safari-web-extension://"].contains { origin.hasPrefix($0) }
    }
}
