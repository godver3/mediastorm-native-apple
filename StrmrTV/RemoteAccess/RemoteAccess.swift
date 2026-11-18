import Foundation
import Network
import Security

private let log = AppLog(category: "RemoteAccess")

/// Remote access over iroh, as the Expo app pairs it: a connection code from the server's
/// admin UI resolves (mainline DHT) to the server's invite; a loopback proxy tunnels HTTP to it;
/// claiming the code registers this device with a fresh pairing credential. The server drops a
/// claimed code from the DHT, so later launches reconnect through the stored invite (its NodeID
/// is stable) and never resolve again. The proxy's port changes per launch, so the pairing, not
/// a URL, is what gets saved.
@MainActor
final class RemoteAccess {
    static let shared = RemoteAccess()

    /// Saved in the Keychain.
    struct Pairing: Codable {
        let invite: String
        /// 32 random bytes, base64url: sent as `X-Remote-Access-Credential` with this device's
        /// `X-Client-ID` on every proxied request.
        let credential: String
        let connectionCode: String
    }

    private(set) var pairing: Pairing?
    /// Why `pairing` is nil although one may be saved: the Keychain read failed or the saved
    /// item didn't decode. Such a launch is not "unpaired", so nothing may forget the pairing
    /// on its account; `reload()` tries again.
    private(set) var loadProblem: String?
    private var connecting: Task<URL, Error>?
    private var pathMonitor: NWPathMonitor?

    private static let keychainAccount = "remoteAccess"

    private init() {
        reload()
    }

    /// Reads the saved pairing when none is loaded; true once one is in hand.
    @discardableResult
    func reload() -> Bool {
        guard pairing == nil else { return true }
        switch Keychain.lookup(Self.keychainAccount) {
        case let .found(data):
            if let saved = try? JSONDecoder().decode(Pairing.self, from: data) {
                if loadProblem != nil { log.notice("saved pairing read after an earlier failure") }
                pairing = saved
                loadProblem = nil
                return true
            }
            loadProblem = "the saved pairing didn't decode (\(data.count) bytes)"
        case .notFound:
            loadProblem = nil
            return false
        case let .failed(status):
            loadProblem = "the Keychain read failed (OSStatus \(status))"
        }
        log.error("remote access pairing not loaded: \(loadProblem ?? "")")
        return false
    }

    /// At launch, a pairing that couldn't be read (as opposed to a missing one) gets a few
    /// more reads a second apart before startup gives up on it for now, keeping it saved.
    func retryUnreadablePairing() async {
        guard pairing == nil, loadProblem != nil else { return }
        for _ in 0..<5 {
            try? await Task.sleep(for: .seconds(1))
            if reload() || loadProblem == nil { return }
        }
        log.error("startup: keeping the saved pairing unread; \(loadProblem ?? "")")
    }

    // MARK: Pairing

    /// Pairs with the server behind `code`; returns the proxy's base URL.
    func pair(code: String) async throws -> URL {
        guard let code = Self.normalize(code) else {
            throw IrohBridge.Failure(message: String(localized: "Enter the connection code from your server, like mshost-ABC123-DEF456-GHJ789."))
        }
        log.info("pairing with code \(code.prefix(13))…")
        let invite = try await IrohBridge.resolve(code: code)
        await IrohBridge.invalidateProxy()  // a proxy for a previous server
        let base = try await IrohBridge.startProxy(invite: invite)
        let credential = Self.makeCredential()
        try await prime(base, credential: credential)
        try await claim(code: code, credential: credential, base: base)
        let pairing = Pairing(invite: invite, credential: credential, connectionCode: code)
        if let data = try? JSONEncoder().encode(pairing), !Keychain.write(data, account: Self.keychainAccount) {
            log.error("paired, but the pairing couldn't be saved to the Keychain; it lasts until the app quits")
        }
        self.pairing = pairing
        loadProblem = nil
        startPathMonitor()
        log.info("paired; proxy at \(base.absoluteString)")
        return base
    }

    /// The proxy's base URL for the saved pairing: the running proxy when it still answers,
    /// else a fresh one. Concurrent callers share one attempt.
    func connect() async throws -> URL {
        if let connecting { return try await connecting.value }
        guard let pairing else { throw IrohBridge.Failure(message: "Not paired") }
        let task = Task { () throws -> URL in
            await IrohBridge.networkChanged()
            if let base = try? await IrohBridge.startProxy(invite: pairing.invite),
               (try? await prime(base, credential: pairing.credential)) != nil {
                return base
            }
            // A proxy on a dead path can keep its listener; start over.
            log.notice("proxy unhealthy; restarting")
            await IrohBridge.invalidateProxy()
            let base = try await IrohBridge.startProxy(invite: pairing.invite)
            try await prime(base, credential: pairing.credential)
            return base
        }
        connecting = task
        defer { connecting = nil }
        let base = try await task.value
        startPathMonitor()
        return base
    }

    /// Unpairs this device (Change Server, sign-out of a remote server). The reason is logged,
    /// so a report of a lost pairing shows what dropped it.
    func forget(reason: String) {
        log.notice("forgetting the remote access pairing (\(pairing == nil ? "none loaded" : "paired")): \(reason)")
        pairing = nil
        loadProblem = nil
        Keychain.delete(Self.keychainAccount)
        pathMonitor?.cancel()
        pathMonitor = nil
        Task { await IrohBridge.invalidateProxy() }
    }

    // MARK: Requests

    /// `GET /health` through the proxy with this device's identity. Also primes the proxy: it
    /// remembers the first client ID and credential it sees and adds them to every later
    /// request, so header-less media requests (AVPlayer) pass the server's pairing check.
    private func prime(_ base: URL, credential: String) async throws {
        var req = URLRequest(url: base.appending(path: "/health"))
        req.timeoutInterval = 10
        req.setValue(Config.clientID, forHTTPHeaderField: "X-Client-ID")
        req.setValue(credential, forHTTPHeaderField: "X-Remote-Access-Credential")
        let (_, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw IrohBridge.Failure(message: String(localized: "The server didn't answer over remote access."))
        }
    }

    /// `POST /api/remote-access/invites/claim`: registers this device under the code.
    private func claim(code: String, credential: String, base: URL) async throws {
        var req = URLRequest(url: base.appending(path: "/api/remote-access/invites/claim"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.clientID, forHTTPHeaderField: "X-Client-ID")
        req.setValue(credential, forHTTPHeaderField: "X-Remote-Access-Credential")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["token": code, "peerId": Config.clientID, "credential": credential])
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            struct Failure: Decodable { let error: String? }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw IrohBridge.Failure(message: message ?? String(localized: "The server refused the code (HTTP \(status))."))
        }
    }

    // MARK: Network changes

    /// iroh is told when the network changes, so it moves to a live path at once rather than
    /// after its idle timeout. The monitor's first report is the current state, not a change.
    private func startPathMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        // Touched only on the monitor's serial queue.
        final class Seen: @unchecked Sendable { var first = true }
        let seen = Seen()
        monitor.pathUpdateHandler = { _ in
            if seen.first { seen.first = false; return }
            Task { await IrohBridge.networkChanged() }
        }
        monitor.start(queue: DispatchQueue(label: "com.strmr.app.nx.iroh-path"))
        pathMonitor = monitor
    }

    // MARK: Codes

    /// Crockford base32 without I, L, O, U.
    private static let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// `mshost-` plus two or three groups of six, folded as the server encodes them (case,
    /// O→0, I/L→1, separators optional), as the Expo login screen accepts them. Nil otherwise.
    static func normalize(_ input: String) -> String? {
        var compact = input.filter { $0.isLetter || $0.isNumber }.uppercased()
        if compact.hasPrefix("MSHOST") { compact.removeFirst(6) }
        let body = compact.map { c -> Character in
            switch c { case "O": "0"; case "I", "L": "1"; default: c }
        }.filter { alphabet.contains($0) }
        guard body.count == 12 || body.count == 18 else { return nil }
        let groups = stride(from: 0, to: body.count, by: 6).map { String(body[$0..<$0 + 6]) }
        return "mshost-" + groups.joined(separator: "-")
    }

    private static func makeCredential() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
