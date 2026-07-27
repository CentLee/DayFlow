import Foundation

protocol APIClientProtocol: Sendable {
    var hasActiveSession: Bool { get }

    func login(email: String, password: String) async throws
    func register(email: String, displayName: String, password: String, inviteCode: String) async throws
    func fetchCurrentSession() async throws -> MeResponse
    func fetchBudget(monthKey: String) async throws -> BudgetBoardResponse
    func saveBudget(monthKey: String, board: BudgetBoardResponse) async throws -> BudgetBoardResponse
    func clearSession()
}

protocol SessionTokenStore: AnyObject, Sendable {
    var token: String? { get set }
}

final class UserDefaultsSessionTokenStore: SessionTokenStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let tokenKey = "dayflow.session.token"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var token: String? {
        get { defaults.string(forKey: tokenKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: tokenKey)
            } else {
                defaults.removeObject(forKey: tokenKey)
            }
        }
    }
}

enum APIClientError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidResponse
    case missingSession
    case unauthorized(String)
    case server(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "API 주소 설정이 올바르지 않습니다."
        case .invalidResponse:
            return "서버 응답을 확인할 수 없습니다."
        case .missingSession:
            return "로그인이 필요합니다."
        case let .unauthorized(message), let .server(message), let .transport(message):
            return message
        }
    }
}

struct APIClient: APIClientProtocol, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: SessionTokenStore

    init(
        baseURL: URL,
        session: URLSession = .shared,
        tokenStore: SessionTokenStore = UserDefaultsSessionTokenStore()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = tokenStore
    }

    var hasActiveSession: Bool {
        tokenStore.token?.isEmpty == false
    }

    static func live() -> APIClient {
        let environment = ProcessInfo.processInfo.environment
        let baseURLString = environment["DAYFLOW_API_BASE_URL"] ?? "http://127.0.0.1:8080/v1"
        guard let baseURL = URL(string: baseURLString) else {
            preconditionFailure("Invalid DAYFLOW_API_BASE_URL: \(baseURLString)")
        }
        return APIClient(baseURL: baseURL)
    }

    func login(email: String, password: String) async throws {
        let response: AuthResponse = try await send(
            path: "auth/login",
            method: "POST",
            body: LoginRequest(email: email, password: password)
        )
        tokenStore.token = response.token
    }

    func register(email: String, displayName: String, password: String, inviteCode: String) async throws {
        let response: AuthResponse = try await send(
            path: "auth/register",
            method: "POST",
            body: RegisterRequest(email: email, displayName: displayName, password: password, inviteCode: inviteCode)
        )
        tokenStore.token = response.token
    }

    func fetchCurrentSession() async throws -> MeResponse {
        try await send(path: "me", method: "GET", requiresAuthorization: true)
    }

    func fetchBudget(monthKey: String) async throws -> BudgetBoardResponse {
        try await send(path: "budget/months/\(monthKey)", method: "GET", requiresAuthorization: true)
    }

    func saveBudget(monthKey: String, board: BudgetBoardResponse) async throws -> BudgetBoardResponse {
        try await send(path: "budget/months/\(monthKey)", method: "PUT", body: board, requiresAuthorization: true)
    }

    func clearSession() {
        tokenStore.token = nil
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        requiresAuthorization: Bool = false
    ) async throws -> Response {
        try await sendData(path: path, method: method, body: nil, requiresAuthorization: requiresAuthorization)
    }

    private func send<RequestBody: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: RequestBody,
        requiresAuthorization: Bool = false
    ) async throws -> Response {
        let bodyData = try Self.makeEncoder().encode(body)
        return try await sendData(path: path, method: method, body: bodyData, requiresAuthorization: requiresAuthorization)
    }

    private func sendData<Response: Decodable>(
        path: String,
        method: String,
        body: Data?,
        requiresAuthorization: Bool
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if requiresAuthorization {
            guard let token = tokenStore.token, token.isEmpty == false else {
                throw APIClientError.missingSession
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIClientError.invalidResponse
            }

            guard 200 ..< 300 ~= httpResponse.statusCode else {
                if let errorResponse = try? Self.makeDecoder().decode(APIErrorResponse.self, from: data) {
                    if httpResponse.statusCode == 401 {
                        throw APIClientError.unauthorized(errorResponse.error.message)
                    }
                    throw APIClientError.server(errorResponse.error.message)
                }

                if httpResponse.statusCode == 401 {
                    throw APIClientError.unauthorized("세션이 만료되었습니다. 다시 로그인해 주세요.")
                }
                throw APIClientError.server("요청을 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.")
            }

            do {
                return try Self.makeDecoder().decode(Response.self, from: data)
            } catch {
                throw APIClientError.invalidResponse
            }
        } catch let error as APIClientError {
            throw error
        } catch {
            throw APIClientError.transport("서버에 연결할 수 없습니다. API 실행 상태를 확인해 주세요.")
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

private struct LoginRequest: Encodable {
    let email: String
    let password: String
}

private struct RegisterRequest: Encodable {
    let email: String
    let displayName: String
    let password: String
    let inviteCode: String
}
