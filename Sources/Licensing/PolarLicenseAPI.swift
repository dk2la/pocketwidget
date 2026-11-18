import Foundation

/// `LicenseAPI` backed by Polar's customer-portal license key endpoints
/// (https://polar.sh/docs/api-reference/customer_portal/activate-license-key).
/// The endpoints are public: the License key itself is the credential, so no
/// API key ships in the app.
///
/// Deliberately conservative: only an explicit, decodable answer from the
/// store counts as "invalid". Timeouts, HTTP 429/5xx and unreadable bodies are
/// `.network`, because a wrong "invalid" locks a paying customer out.
struct PolarLicenseAPI: LicenseAPI {
    /// One HTTP round trip. Injected so tests can answer with canned bodies.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let baseURL: URL?
    private let organizationID: String
    private let transport: Transport

    /// - Parameters:
    ///   - baseURL: the API host, e.g. `https://api.polar.sh`.
    ///   - organizationID: the store's organization; keys of any other
    ///     organization are unknown to these endpoints.
    init(
        baseURL: URL?,
        organizationID: String,
        transport: @escaping Transport = PolarLicenseAPI.urlSession
    ) {
        self.baseURL = baseURL
        self.organizationID = organizationID
        self.transport = transport
    }

    /// Default transport: an ephemeral session, so nothing is cached on disk.
    static let urlSession: Transport = { request in
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    // MARK: - LicenseAPI

    func activate(licenseKey: String, activationName: String) async throws -> LicenseActivation {
        let (status, data) = try await post("activate", ["key": licenseKey, "label": activationName])
        switch status {
        case 200:
            guard let activation = Self.decode(PolarActivation.self, from: data) else {
                throw LicenseAPIError.network
            }
            return LicenseActivation(activationID: activation.id, productID: activation.licenseKey.benefitId)
        case 403:
            // Revoked, disabled or expired keys and a full Activation limit
            // share this status; only the message tells them apart.
            guard let refusal = Self.refusal(in: data, named: "NotPermitted") else {
                throw LicenseAPIError.network
            }
            throw refusal.detail.localizedCaseInsensitiveContains("activation limit")
                ? LicenseAPIError.activationLimitReached
                : LicenseAPIError.invalidKey
        case 404:
            guard Self.refusal(in: data, named: "ResourceNotFound") != nil else {
                throw LicenseAPIError.network
            }
            throw LicenseAPIError.invalidKey
        default:
            throw LicenseAPIError.network
        }
    }

    func validate(licenseKey: String, activationID: String) async throws -> LicenseValidity {
        let (status, data) = try await post("validate", ["key": licenseKey, "activation_id": activationID])
        switch status {
        case 200:
            guard let key = Self.decode(PolarKey.self, from: data), key.status == "granted" else {
                throw LicenseAPIError.network
            }
            return .valid
        case 404:
            // Unknown, revoked, disabled or expired key, or the Activation
            // was removed.
            guard Self.refusal(in: data, named: "ResourceNotFound") != nil else {
                throw LicenseAPIError.network
            }
            return .invalid
        default:
            throw LicenseAPIError.network
        }
    }

    func deactivate(licenseKey: String, activationID: String) async throws {
        let (status, data) = try await post("deactivate", ["key": licenseKey, "activation_id": activationID])
        switch status {
        case 204:
            return
        case 404:
            guard Self.refusal(in: data, named: "ResourceNotFound") != nil else {
                throw LicenseAPIError.network
            }
            throw LicenseAPIError.invalidKey
        default:
            throw LicenseAPIError.network
        }
    }

    // MARK: - Wire

    /// Sends one JSON POST and returns the status with the raw body. Throws
    /// `.network` when there is no answer at all.
    private func post(_ action: String, _ fields: [String: String]) async throws -> (Int, Data) {
        var body = fields
        body["organization_id"] = organizationID
        guard let baseURL else { throw LicenseAPIError.network }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/customer-portal/license-keys/" + action))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            let (data, response) = try await transport(request)
            return (response.statusCode, data)
        } catch {
            throw LicenseAPIError.network
        }
    }

    private static func decode<Answer: Decodable>(_ type: Answer.Type, from data: Data) -> Answer? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(type, from: data)
    }

    /// The store's own error body, if `data` is one of the expected kind. A
    /// 403 or 404 without it (a proxy, a captive portal) proves nothing
    /// about the key.
    private static func refusal(in data: Data, named name: String) -> PolarRefusal? {
        guard let refusal = decode(PolarRefusal.self, from: data), refusal.error == name else { return nil }
        return refusal
    }
}

/// The parts of Polar's responses Pocket reads. Decoded with
/// `.convertFromSnakeCase`.
private struct PolarActivation: Decodable {
    var id: String
    var licenseKey: Key

    struct Key: Decodable {
        /// Identifies the license-key benefit, and with it the product sold.
        var benefitId: String
    }
}

private struct PolarKey: Decodable {
    var id: String
    var status: String
}

private struct PolarRefusal: Decodable {
    var error: String
    var detail: String
}
