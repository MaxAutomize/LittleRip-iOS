import Foundation

struct SmartRentCredentials: Codable {
    var email: String
    var password: String
}

struct SmartRentLock: Codable, Identifiable {
    var id: Int
    var name: String
    var locked: Bool?
}

enum SmartRentError: LocalizedError {
    case missingCredentials
    case invalidResponse
    case noLockFound
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Missing SmartRent credentials. Open LittleRip and save them first."
        case .invalidResponse: return "Invalid SmartRent response."
        case .noLockFound: return "No SmartRent lock found."
        case .api(let message): return message
        }
    }
}

final class SmartRentClient {
    static let appGroup = "group.com.maxautomize.LittleRip"

    private let email: String
    private let password: String
    private var accessToken: String?
    private var refreshToken: String?
    private var expires: Int?

    init(email: String, password: String) {
        self.email = email
        self.password = password
    }

    static func loadCredentials() throws -> SmartRentCredentials {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let email = defaults.string(forKey: "smartrent.email"),
              let password = defaults.string(forKey: "smartrent.password"),
              !email.isEmpty,
              !password.isEmpty else {
            throw SmartRentError.missingCredentials
        }
        return SmartRentCredentials(email: email, password: password)
    }

    static func saveCredentials(email: String, password: String) {
        let defaults = UserDefaults(suiteName: appGroup) ?? .standard
        defaults.set(email, forKey: "smartrent.email")
        defaults.set(password, forKey: "smartrent.password")
        defaults.synchronize()
    }

    static func setWidgetStatus(_ message: String) {
        let defaults = UserDefaults(suiteName: appGroup) ?? .standard
        defaults.set(message, forKey: "smartrent.widgetStatus")
        defaults.set(Date().timeIntervalSince1970, forKey: "smartrent.widgetStatusAt")
        defaults.synchronize()
    }

    static func widgetStatus() -> String {
        let defaults = UserDefaults(suiteName: appGroup) ?? .standard
        return defaults.string(forKey: "smartrent.widgetStatus") ?? "Ready"
    }

    func unlockFrontDoor() async throws {
        let lock = try await firstFrontDoorLock()
        try await setLocked(lock, locked: false)
    }

    func lockFrontDoor() async throws {
        let lock = try await firstFrontDoorLock()
        try await setLocked(lock, locked: true)
    }

    func firstFrontDoorLock() async throws -> SmartRentLock {
        try await loginIfNeeded()
        let hubs = try await getJSON("https://control.smartrent.com/api/v2/hubs")
        guard let hubArray = hubs as? [[String: Any]] else { throw SmartRentError.invalidResponse }

        var locks: [SmartRentLock] = []
        for hub in hubArray {
            guard let hubId = hub["id"] else { continue }
            let devices = try await getJSON("https://control.smartrent.com/api/v2/hubs/\(hubId)/devices")
            guard let deviceArray = devices as? [[String: Any]] else { continue }
            for device in deviceArray {
                guard (device["type"] as? String) == "entry_control",
                      let id = device["id"] as? Int else { continue }
                let name = device["name"] as? String ?? "Lock"
                let attrs = (device["attributes"] as? [[String: Any]]) ?? []
                let lockedAttr = attrs.first { ($0["name"] as? String) == "locked" }
                let lockedString = lockedAttr?["value"] as? String ?? lockedAttr?["last_read_state"] as? String
                let locked = lockedString.map { $0 == "true" }
                locks.append(SmartRentLock(id: id, name: name, locked: locked))
            }
        }

        if let front = locks.first(where: { $0.name.lowercased().contains("front") || $0.name.lowercased().contains("door") }) {
            return front
        }
        guard let first = locks.first else { throw SmartRentError.noLockFound }
        return first
    }

    private func loginIfNeeded() async throws {
        if let expires, let accessToken, expires > Int(Date().timeIntervalSince1970) + 60, !accessToken.isEmpty {
            return
        }

        var request = URLRequest(url: URL(string: "https://control.smartrent.com/api/v2/sessions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SmartRentError.invalidResponse }
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            let message = String(data: data, encoding: .utf8) ?? "Login failed"
            throw SmartRentError.api(message)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = (json?["data"] as? [String: Any]) ?? json
        guard let access = payload?["access_token"] as? String else { throw SmartRentError.invalidResponse }
        self.accessToken = access
        self.refreshToken = payload?["refresh_token"] as? String
        self.expires = payload?["expires"] as? Int
    }

    private func getJSON(_ urlString: String) async throws -> Any {
        try await loginIfNeeded()
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 300 else {
            throw SmartRentError.api(String(data: data, encoding: .utf8) ?? "Request failed")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func setLocked(_ lock: SmartRentLock, locked: Bool) async throws {
        try await loginIfNeeded()
        guard let token = accessToken else { throw SmartRentError.invalidResponse }

        let url = URL(string: "wss://control.smartrent.com/socket/websocket?token=\(token)&vsn=2.0.0")!
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()

        let join = "[\"null\",\"null\",\"devices:\(lock.id)\",\"phx_join\",{}]"
        try await task.send(.string(join))
        _ = try? await task.receive()

        let value = locked ? "true" : "false"
        let command = "[\"null\",\"null\",\"devices:\(lock.id)\",\"update_attributes\",{\"device_id\":\(lock.id),\"attributes\":[{\"name\":\"locked\",\"value\":\"\(value)\"}]}]"
        try await task.send(.string(command))

        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            do {
                _ = try await task.receive()
                break
            } catch {
                break
            }
        }
        task.cancel(with: .goingAway, reason: nil)
    }
}
