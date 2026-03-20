import Foundation

struct RuntimeServerHealth: Decodable {
    let version: String
}

struct NeoCodeRuntimeHealthClient {
    func waitUntilHealthy(baseURL: URL, username: String, password: String, timeout: TimeInterval) async throws -> RuntimeServerHealth {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            do {
                return try await health(baseURL: baseURL, username: username, password: password)
            } catch {
                try await Task.sleep(for: .milliseconds(250))
            }
        }

        throw OpenCodeRuntimeError.healthCheckTimedOut
    }

    private func health(baseURL: URL, username: String, password: String) async throws -> RuntimeServerHealth {
        let url = baseURL.appending(path: "/v1/server")
        var request = URLRequest(url: url)
        request.setValue(Self.authorizationHeader(username: username, password: password), forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode
        else {
            throw OpenCodeRuntimeError.invalidServerResponse
        }

        return try JSONDecoder().decode(RuntimeServerHealth.self, from: data)
    }

    private static func authorizationHeader(username: String, password: String) -> String {
        let token = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(token)"
    }
}
