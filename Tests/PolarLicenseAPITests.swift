import XCTest

/// Bodies and statuses are the ones Polar's sandbox answered with on
/// 2026-11-18, trimmed to what matters.
final class PolarLicenseAPITests: XCTestCase {
    /// Records what the client sent; the transport is called off the test's
    /// own task, hence the actor.
    private actor Recorder {
        private(set) var requests: [URLRequest] = []

        func record(_ request: URLRequest) {
            requests.append(request)
        }
    }

    private static let organizationID = "11111111-1111-4111-8111-111111111111"
    private static let benefitID = "22222222-2222-4222-8222-222222222222"
    private static let activationID = "33333333-3333-4333-8333-333333333333"

    private func api(status: Int, body: String, recorder: Recorder? = nil) -> PolarLicenseAPI {
        PolarLicenseAPI(
            baseURL: URL(string: "https://api.polar.test"),
            organizationID: Self.organizationID
        ) { request in
            await recorder?.record(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
            else { throw URLError(.badURL) }
            return (Data(body.utf8), response)
        }
    }

    private var offline: PolarLicenseAPI {
        PolarLicenseAPI(baseURL: URL(string: "https://api.polar.test"), organizationID: Self.organizationID) { _ in
            throw URLError(.notConnectedToInternet)
        }
    }

    private func assertThrows<T: Sendable>(
        _ expected: LicenseAPIError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ call: () async throws -> T
    ) async {
        do {
            _ = try await call()
            XCTFail("expected \(expected), but the call returned", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LicenseAPIError, expected, file: file, line: line)
        }
    }

    private static let keyJSON = """
    {"id": "44444444-4444-4444-8444-444444444444", "organization_id": "\(organizationID)",
     "benefit_id": "\(benefitID)", "key": "POCKET-TEST", "display_key": "****-TEST",
     "status": "granted", "limit_activations": 3, "usage": 0, "limit_usage": null,
     "validations": 1, "last_validated_at": null, "expires_at": null,
     "customer": {"id": "55555555-5555-4555-8555-555555555555", "email": "buyer@example.com", "name": "John Doe"}}
    """

    private static let activatedJSON = """
    {"id": "\(activationID)", "license_key_id": "44444444-4444-4444-8444-444444444444",
     "label": "Test Mac", "meta": {}, "created_at": "2026-11-18T17:52:24.552504Z", "modified_at": null,
     "license_key": \(keyJSON)}
    """

    private static let notFoundJSON = #"{"error": "ResourceNotFound", "detail": "Not found"}"#
    private static let limitReachedJSON =
        #"{"error": "NotPermitted", "detail": "License key activation limit already reached"}"#

    private func json(_ request: URLRequest) throws -> [String: String] {
        let object = try JSONSerialization.jsonObject(with: request.httpBody ?? Data())
        return try XCTUnwrap(object as? [String: String])
    }

    // MARK: - Requests

    func testActivateSendsJSONPost() async throws {
        let recorder = Recorder()
        _ = try await api(status: 200, body: Self.activatedJSON, recorder: recorder)
            .activate(licenseKey: "AB+C&D=E/F", activationName: "Данила's Mac #1")

        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.polar.test/v1/customer-portal/license-keys/activate"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(try json(request), [
            "key": "AB+C&D=E/F",
            "label": "Данила's Mac #1",
            "organization_id": Self.organizationID,
        ])
    }

    func testValidateAndDeactivateSendKeyAndActivation() async throws {
        let recorder = Recorder()
        _ = try await api(status: 200, body: Self.keyJSON, recorder: recorder)
            .validate(licenseKey: "KEY-1", activationID: Self.activationID)
        try await api(status: 204, body: "", recorder: recorder)
            .deactivate(licenseKey: "KEY-1", activationID: Self.activationID)

        let requests = await recorder.requests
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, [
            "https://api.polar.test/v1/customer-portal/license-keys/validate",
            "https://api.polar.test/v1/customer-portal/license-keys/deactivate",
        ])
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(try json(request), [
                "key": "KEY-1",
                "activation_id": Self.activationID,
                "organization_id": Self.organizationID,
            ])
        }
    }

    func testMissingBaseURLIsANetworkFailure() async {
        let api = PolarLicenseAPI(baseURL: nil, organizationID: Self.organizationID) { _ in
            XCTFail("nothing should be sent")
            throw URLError(.badURL)
        }
        await assertThrows(.network) { try await api.activate(licenseKey: "KEY-1", activationName: "Test Mac") }
    }

    // MARK: - Activate

    func testActivateReturnsActivationAndBenefit() async throws {
        let activation = try await api(status: 200, body: Self.activatedJSON)
            .activate(licenseKey: "KEY-1", activationName: "Test Mac")
        XCTAssertEqual(activation, LicenseActivation(activationID: Self.activationID, productID: Self.benefitID))
    }

    func testActivateUnknownKeyIsInvalidKey() async {
        let api = api(status: 404, body: Self.notFoundJSON)
        await assertThrows(.invalidKey) { try await api.activate(licenseKey: "NOPE", activationName: "Test Mac") }
    }

    func testActivateRevokedKeyIsInvalidKey() async {
        let api = api(status: 403, body: #"{"error": "NotPermitted", "detail": "License key is no longer active."}"#)
        await assertThrows(.invalidKey) { try await api.activate(licenseKey: "KEY-1", activationName: "Test Mac") }
    }

    func testActivateLimitReached() async {
        let api = api(status: 403, body: Self.limitReachedJSON)
        await assertThrows(.activationLimitReached) {
            try await api.activate(licenseKey: "KEY-1", activationName: "Test Mac")
        }
    }

    func testActivateNetworkFailures() async {
        let offline = offline
        await assertThrows(.network) { try await offline.activate(licenseKey: "KEY-1", activationName: "Test Mac") }

        // Only the store's own refusal is trusted. Polar's rate limit answers
        // 429 with an empty body.
        let unreadable: [(status: Int, body: String)] = [
            (429, ""),
            (429, Self.notFoundJSON),
            (500, Self.notFoundJSON),
            (503, "<html>Service Unavailable</html>"),
            (200, "not json"),
            (200, "{}"),
            (403, "<html>Blocked by the network</html>"),
            (403, Self.notFoundJSON),
            (404, "<html>Not Found</html>"),
            (404, Self.limitReachedJSON),
            (422, #"{"detail": [{"loc": ["body", "key"], "msg": "Field required", "type": "missing"}]}"#),
            // Claims success but lacks the license key: no product to check.
            (200, #"{"id": "\#(Self.activationID)", "label": "Test Mac"}"#),
        ]
        for answer in unreadable {
            let api = api(status: answer.status, body: answer.body)
            await assertThrows(.network) { try await api.activate(licenseKey: "KEY-1", activationName: "Test Mac") }
        }
    }

    // MARK: - Validate

    func testValidateValid() async throws {
        let validity = try await api(status: 200, body: Self.keyJSON)
            .validate(licenseKey: "KEY-1", activationID: Self.activationID)
        XCTAssertEqual(validity, .valid)
    }

    func testValidateNotFoundIsInvalid() async throws {
        // Polar answers 404 for a revoked, disabled or expired key and for a
        // removed Activation alike.
        let validity = try await api(status: 404, body: Self.notFoundJSON)
            .validate(licenseKey: "KEY-1", activationID: Self.activationID)
        XCTAssertEqual(validity, .invalid)
    }

    func testValidateNetworkFailures() async {
        let offline = offline
        await assertThrows(.network) {
            try await offline.validate(licenseKey: "KEY-1", activationID: Self.activationID)
        }

        let unreadable: [(status: Int, body: String)] = [
            (429, ""),
            (500, Self.notFoundJSON),
            (502, "Bad Gateway"),
            (404, "<html>Not Found</html>"),
            (404, #"{"error": "SomethingElse", "detail": "Not found"}"#),
            (403, Self.limitReachedJSON),
            (200, ""),
            (200, #"{"error": "Something went wrong."}"#),
            // An answer that is not a granted key proves nothing either way.
            (200, #"{"id": "44444444-4444-4444-8444-444444444444", "status": "revoked"}"#),
        ]
        for answer in unreadable {
            let api = api(status: answer.status, body: answer.body)
            await assertThrows(.network) {
                try await api.validate(licenseKey: "KEY-1", activationID: Self.activationID)
            }
        }
    }

    // MARK: - Deactivate

    func testDeactivateSucceeds() async throws {
        try await api(status: 204, body: "").deactivate(licenseKey: "KEY-1", activationID: Self.activationID)
    }

    func testDeactivateUnknownActivationIsInvalidKey() async {
        let api = api(status: 404, body: Self.notFoundJSON)
        await assertThrows(.invalidKey) { try await api.deactivate(licenseKey: "KEY-1", activationID: "gone") }
    }

    func testDeactivateNetworkFailures() async {
        let offline = offline
        await assertThrows(.network) {
            try await offline.deactivate(licenseKey: "KEY-1", activationID: Self.activationID)
        }

        let unreadable: [(status: Int, body: String)] = [
            (429, ""),
            (500, Self.notFoundJSON),
            (404, "<html>Not Found</html>"),
            (200, "{}"),
        ]
        for answer in unreadable {
            let api = api(status: answer.status, body: answer.body)
            await assertThrows(.network) {
                try await api.deactivate(licenseKey: "KEY-1", activationID: Self.activationID)
            }
        }
    }
}
