import Foundation
import Testing
@testable import DayFlow

@Suite
struct APIClientTransportTests {
    @Test
    func loginUsesTransportStoresTokenAndDecodesCurrentSession() async throws {
        APIClientURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIClientURLProtocol.self]
        let tokenStore = TestSessionTokenStore()
        let client = APIClient(
            baseURL: try #require(URL(string: "https://dayflow.test/v1")),
            session: URLSession(configuration: configuration),
            tokenStore: tokenStore
        )

        try await client.login(email: "owner@dayflow.local", password: "secret1234")

        let loginRequest = try #require(APIClientURLProtocol.request(for: "/v1/auth/login"))
        #expect(loginRequest.httpMethod == "POST")
        #expect(loginRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let loginBody = try loginRequest.bodyData()
        #expect(try JSONDecoder().decode(LoginPayload.self, from: loginBody) == LoginPayload(email: "owner@dayflow.local", password: "secret1234"))
        #expect(tokenStore.token == "test-token")

        let session = try await client.fetchCurrentSession()

        let meRequest = try #require(APIClientURLProtocol.request(for: "/v1/me"))
        #expect(meRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(session.user.email == "owner@dayflow.local")
        #expect(session.ownedCalendars.map(\.id) == ["cal_personal"])
        #expect(session.sharedCalendars.map(\.id) == ["cal_shared"])
        #expect(session.currentBudgetMonthKey == "2026-03")
    }
}

private struct LoginPayload: Codable, Equatable {
    let email: String
    let password: String
}

private enum RequestBodyError: Error {
    case missingBody
    case streamReadFailed
}

private extension URLRequest {
    func bodyData() throws -> Data {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else {
            throw RequestBodyError.missingBody
        }

        httpBodyStream.open()
        defer { httpBodyStream.close() }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024)
        defer { buffer.deallocate() }

        var data = Data()
        while true {
            let bytesRead = httpBodyStream.read(buffer, maxLength: 1_024)
            if bytesRead < 0 {
                throw httpBodyStream.streamError ?? RequestBodyError.streamReadFailed
            }
            if bytesRead == 0 {
                return data
            }
            data.append(buffer, count: bytesRead)
        }
    }
}

private final class TestSessionTokenStore: SessionTokenStore, @unchecked Sendable {
    var token: String?
}

private final class APIClientURLProtocol: URLProtocol, @unchecked Sendable {
    private static let requests = RequestStore()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "dayflow.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let client, let url = request.url else {
            return
        }

        Self.requests.record(request)
        let body: Data
        switch url.path {
        case "/v1/auth/login":
            body = #"{"user":{"id":"usr_owner","email":"owner@dayflow.local","display_name":"DayFlow Owner"},"token":"test-token"}"#.data(using: .utf8)!
        case "/v1/me":
            body = ##"{"user":{"id":"usr_owner","email":"owner@dayflow.local","display_name":"DayFlow Owner"},"personal_calendar":{"id":"cal_personal","name":"Personal","color":"#1F6B5C","updated_at":"2026-03-17T00:00:00Z"},"shared_calendars":[{"id":"cal_shared","name":"Shared","color":"#D8A21D","updated_at":"2026-03-17T00:00:00Z"}],"current_budget_month_key":"2026-03"}"##.data(using: .utf8)!
        default:
            client.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        client.urlProtocol(
            self,
            didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!,
            cacheStoragePolicy: .notAllowed
        )
        client.urlProtocol(self, didLoad: body)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        requests.reset()
    }

    static func request(for path: String) -> URLRequest? {
        requests.request(for: path)
    }
}

private final class RequestStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: URLRequest] = [:]

    func record(_ request: URLRequest) {
        lock.lock()
        values[request.url?.path ?? ""] = request
        lock.unlock()
    }

    func reset() {
        lock.lock()
        values.removeAll()
        lock.unlock()
    }

    func request(for path: String) -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return values[path]
    }
}
