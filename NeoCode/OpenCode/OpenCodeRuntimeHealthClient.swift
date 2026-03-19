import Foundation

struct OpenCodeHealth: Decodable {
    let healthy: Bool
    let version: String
}

struct OpenCodeRuntimeHealthClient {
    func waitUntilHealthy(baseURL: URL, username: String, password: String, timeout: TimeInterval) async throws -> OpenCodeHealth {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            do {
                let health = try await health(baseURL: baseURL, username: username, password: password)
                if health.healthy {
                    return health
                }
            } catch {
                try await Task.sleep(for: .milliseconds(250))
                continue
            }

            try await Task.sleep(for: .milliseconds(250))
        }

        throw OpenCodeRuntimeError.healthCheckTimedOut
    }

    private func health(baseURL: URL, username: String, password: String) async throws -> OpenCodeHealth {
        let url = baseURL.appending(path: "/global/health")
        var request = URLRequest(url: url)
        request.setValue(Self.authorizationHeader(username: username, password: password), forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode
        else {
            throw OpenCodeRuntimeError.invalidServerResponse
        }

        return try JSONDecoder().decode(OpenCodeHealth.self, from: data)
    }

    private static func authorizationHeader(username: String, password: String) -> String {
        let token = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(token)"
    }
}
