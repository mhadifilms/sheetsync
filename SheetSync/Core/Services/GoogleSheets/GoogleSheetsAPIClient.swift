import Foundation

@MainActor
class GoogleSheetsAPIClient: ObservableObject {
    static let shared = GoogleSheetsAPIClient()

    private let rateLimiter = RateLimiter()
    private let authService = GoogleAuthService.shared

    private let baseURL = "https://sheets.googleapis.com/v4/spreadsheets"
    private let driveBaseURL = "https://www.googleapis.com/drive/v3/files"

    // Legacy method for compatibility - no longer stores token
    func setAccessToken(_ token: String) {
        // Token is now fetched fresh before each request via authService
    }

    // MARK: - List Spreadsheets

    func listSpreadsheets(pageToken: String? = nil, pageSize: Int = 50) async throws -> GoogleSpreadsheetListResponse {
        try await rateLimiter.waitForReadSlot()

        guard var components = URLComponents(string: driveBaseURL) else {
            throw SyncError.apiError(400, "Invalid Drive API URL")
        }
        var queryItems = [
            URLQueryItem(name: "q", value: "mimeType='application/vnd.google-apps.spreadsheet'"),
            URLQueryItem(name: "fields", value: "files(id,name,modifiedTime,webViewLink),nextPageToken"),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
            // Include shared drives and files shared with user
            URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "corpora", value: "allDrives")
        ]

        if let pageToken = pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw SyncError.apiError(400, "Invalid URL for listing spreadsheets")
        }
        let request = try await buildRequest(url: url)
        return try await performRequest(request)
    }

    // MARK: - Check Modified Time (lightweight - 1 API call)

    func getModifiedTime(id: String) async throws -> Date? {
        try await rateLimiter.waitForReadSlot()

        guard var components = URLComponents(string: "\(driveBaseURL)/\(id)") else {
            throw SyncError.apiError(400, "Invalid file ID")
        }
        components.queryItems = [
            URLQueryItem(name: "fields", value: "modifiedTime"),
            URLQueryItem(name: "supportsAllDrives", value: "true")
        ]

        guard let url = components.url else {
            throw SyncError.apiError(400, "Invalid URL for modified time check")
        }
        let request = try await buildRequest(url: url)
        let response: DriveFileResponse = try await performRequest(request)
        return response.modifiedTime
    }

    // MARK: - Get Spreadsheet Metadata

    func getSpreadsheet(id: String) async throws -> GoogleSpreadsheetResponse {
        try await rateLimiter.waitForReadSlot()

        guard var components = URLComponents(string: "\(baseURL)/\(id)") else {
            throw SyncError.apiError(400, "Invalid spreadsheet ID")
        }
        components.queryItems = [
            URLQueryItem(name: "fields", value: "spreadsheetId,properties,sheets.properties")
        ]

        guard let url = components.url else {
            throw SyncError.apiError(400, "Invalid URL for spreadsheet")
        }
        let request = try await buildRequest(url: url)
        return try await performRequest(request)
    }

    // MARK: - Read Values

    func getValues(spreadsheetId: String, range: String) async throws -> GoogleValuesResponse {
        try await rateLimiter.waitForReadSlot()

        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        guard var components = URLComponents(string: "\(baseURL)/\(spreadsheetId)/values/\(encodedRange)") else {
            throw SyncError.apiError(400, "Invalid range format")
        }
        components.queryItems = [
            URLQueryItem(name: "valueRenderOption", value: "UNFORMATTED_VALUE"),
            URLQueryItem(name: "dateTimeRenderOption", value: "FORMATTED_STRING")
        ]

        guard let url = components.url else {
            throw SyncError.apiError(400, "Invalid URL for values request")
        }
        let request = try await buildRequest(url: url)
        return try await performRequest(request)
    }

    func batchGetValues(spreadsheetId: String, ranges: [String]) async throws -> BatchGetValuesResponse {
        try await rateLimiter.waitForReadSlot()

        guard var components = URLComponents(string: "\(baseURL)/\(spreadsheetId)/values:batchGet") else {
            throw SyncError.apiError(400, "Invalid spreadsheet ID for batch get")
        }
        var queryItems = ranges.map { URLQueryItem(name: "ranges", value: $0) }
        queryItems.append(URLQueryItem(name: "valueRenderOption", value: "UNFORMATTED_VALUE"))
        queryItems.append(URLQueryItem(name: "dateTimeRenderOption", value: "FORMATTED_STRING"))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw SyncError.apiError(400, "Invalid URL for batch get")
        }
        let request = try await buildRequest(url: url)
        return try await performRequest(request)
    }

    // MARK: - Write Values

    func updateValues(spreadsheetId: String, range: String, values: [[String]]) async throws -> UpdateValuesResponse {
        try await rateLimiter.waitForWriteSlot()

        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        guard var components = URLComponents(string: "\(baseURL)/\(spreadsheetId)/values/\(encodedRange)") else {
            throw SyncError.apiError(400, "Invalid range format for update")
        }
        components.queryItems = [
            URLQueryItem(name: "valueInputOption", value: "USER_ENTERED")
        ]

        guard let url = components.url else {
            throw SyncError.apiError(400, "Invalid URL for update")
        }
        var request = try await buildRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ValueRangeRequest(range: range, values: values)
        request.httpBody = try JSONEncoder().encode(body)

        return try await performRequest(request)
    }

    func batchUpdateValues(spreadsheetId: String, data: [GoogleBatchUpdateRequest.ValueRange]) async throws -> GoogleBatchUpdateResponse {
        try await rateLimiter.waitForWriteSlot()

        guard let url = URL(string: "\(baseURL)/\(spreadsheetId)/values:batchUpdate") else {
            throw SyncError.apiError(400, "Invalid spreadsheet ID for batch update")
        }
        var request = try await buildRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GoogleBatchUpdateRequest(
            valueInputOption: "USER_ENTERED",
            data: data
        )
        request.httpBody = try JSONEncoder().encode(body)

        return try await performRequest(request)
    }

    func appendValues(spreadsheetId: String, range: String, values: [[String]]) async throws -> AppendValuesResponse {
        try await rateLimiter.waitForWriteSlot()

        let encodedRange = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? range
        guard var components = URLComponents(string: "\(baseURL)/\(spreadsheetId)/values/\(encodedRange):append") else {
            throw SyncError.apiError(400, "Invalid range format for append")
        }
        components.queryItems = [
            URLQueryItem(name: "valueInputOption", value: "USER_ENTERED"),
            URLQueryItem(name: "insertDataOption", value: "INSERT_ROWS")
        ]

        guard let url = components.url else {
            throw SyncError.apiError(400, "Invalid URL for append")
        }
        var request = try await buildRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ValueRangeRequest(range: range, values: values)
        request.httpBody = try JSONEncoder().encode(body)

        return try await performRequest(request)
    }

    // MARK: - Private Methods

    private func buildRequest(url: URL) async throws -> URLRequest {
        // Fetch a fresh/valid token before each request - this handles automatic refresh
        let token = try await authService.getValidToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                Logger.shared.error("Decode error: \(error), Response: \(String(data: data, encoding: .utf8) ?? "nil")")
                throw SyncError.parseError(error.localizedDescription)
            }
        case 401:
            throw SyncError.notAuthenticated
        case 403:
            throw SyncError.permissionDenied
        case 404:
            throw SyncError.sheetNotFound(request.url?.lastPathComponent ?? "unknown")
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) } ?? 60
            await rateLimiter.handleRateLimitError(retryAfter: retryAfter)
            throw SyncError.rateLimited(retryAfter: retryAfter)
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SyncError.apiError(httpResponse.statusCode, message)
        }
    }
}

// MARK: - Additional Response Types

struct BatchGetValuesResponse: Codable {
    let spreadsheetId: String
    let valueRanges: [GoogleValuesResponse]?
}

struct UpdateValuesResponse: Codable {
    let spreadsheetId: String
    let updatedRange: String?
    let updatedRows: Int?
    let updatedColumns: Int?
    let updatedCells: Int?
}

struct AppendValuesResponse: Codable {
    let spreadsheetId: String
    let tableRange: String?
    let updates: UpdateValuesResponse?
}

struct ValueRangeRequest: Codable {
    let range: String
    let values: [[String]]
}

struct DriveFileResponse: Codable {
    let modifiedTime: Date?

    enum CodingKeys: String, CodingKey {
        case modifiedTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let timeString = try container.decodeIfPresent(String.self, forKey: .modifiedTime) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            modifiedTime = formatter.date(from: timeString)
        } else {
            modifiedTime = nil
        }
    }
}
