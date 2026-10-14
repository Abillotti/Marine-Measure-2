import Foundation
import CoreLocation
import Observation

/// One shared scan in the community database.
struct CommunityScan: Identifiable, Hashable {
    let id: String
    let speciesID: String
    let sizeInches: Double
    let method: String
    let sex: String
    let shell: String
    let verdict: String
    let stateCode: String
    let county: String
    let waterBody: String
    let latitude: Double?
    let longitude: Double?
    let takenAt: Date
    let uid: String

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var sexValue: CrabSex { CrabSex(rawValue: sex) ?? .unknown }
    var verdictValue: VerdictKind { VerdictKind(rawValue: verdict) ?? .noRules }
}

enum CommunityError: LocalizedError {
    case notConfigured
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "The community database isn't set up yet (Settings › Community database)."
        case .server(let message): return message
        case .badResponse: return "The server sent an unexpected response."
        }
    }
}

/// Talks to Cloud Firestore over its REST API (no SDK needed).
///
/// * Every install signs in anonymously with Firebase Auth, so each shared scan
///   carries an owner `uid` and only its owner can delete it.
/// * Locations are rounded to 2 decimals (~1 km) before they leave the phone.
/// * Security rules that validate uploads are in firebase/firestore.rules.
@Observable
final class CommunityService {
    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    var scans: [CommunityScan] = []
    var loadState: LoadState = .idle
    var loadedSpeciesID: String? = nil
    var lastLoaded: Date? = nil
    var indexLink: URL? = nil
    var usingSampleData = false

    @ObservationIgnored private var idToken: String? = nil
    @ObservationIgnored private var userID: String? = nil
    @ObservationIgnored private var tokenExpiry: Date = .distantPast

    var projectID: String {
        let custom = UserDefaults.standard.string(forKey: SettingsKey.firebaseProjectID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? AppConfig.firebaseProjectID : custom
    }

    var apiKey: String {
        let custom = UserDefaults.standard.string(forKey: SettingsKey.firebaseAPIKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? AppConfig.firebaseWebAPIKey : custom
    }

    var isConfigured: Bool { !projectID.isEmpty && !apiKey.isEmpty }

    private var documentsBase: String {
        let project = projectID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectID
        return "https://firestore.googleapis.com/v1/projects/\(project)/databases/(default)/documents"
    }

    private var encodedKey: String {
        apiKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? apiKey
    }

    private var refreshKeychainKey: String { "firebase.refresh.\(projectID)" }

    // MARK: Sharing

    /// Uploads one catch and returns the new document id.
    @MainActor
    func share(_ record: CatchRecord) async throws -> String {
        guard isConfigured else { throw CommunityError.notConfigured }
        let auth = try await validToken()
        let roundedSize = (record.sizeInches * 100).rounded() / 100
        var fields: [String: Any] = [:]
        fields["species"] = CommunityService.stringValue(record.speciesID)
        fields["sizeIn"] = CommunityService.doubleValue(roundedSize)
        fields["method"] = CommunityService.stringValue(record.methodRaw)
        fields["sex"] = CommunityService.stringValue(record.sexRaw)
        fields["shell"] = CommunityService.stringValue(record.shellRaw)
        fields["verdict"] = CommunityService.stringValue(record.verdictRaw)
        fields["state"] = CommunityService.stringValue(record.stateCode)
        fields["county"] = CommunityService.stringValue(record.county)
        fields["waterBody"] = CommunityService.stringValue(record.waterBody)
        fields["takenAt"] = CommunityService.timestampValue(record.date)
        fields["uid"] = CommunityService.stringValue(auth.uid)
        fields["appVersion"] = CommunityService.stringValue(AppConfig.appVersion)
        if let latitude = record.latitude, let longitude = record.longitude {
            // Rounded to 2 decimals (about 1 km) for privacy.
            let roundedLatitude = (latitude * 100).rounded() / 100
            let roundedLongitude = (longitude * 100).rounded() / 100
            fields["lat"] = CommunityService.doubleValue(roundedLatitude)
            fields["lon"] = CommunityService.doubleValue(roundedLongitude)
        }
        guard let url = URL(string: documentsBase + "/" + AppConfig.communityCollection) else {
            throw CommunityError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])
        let object = try await send(request)
        guard let json = object as? [String: Any],
              let name = json["name"] as? String,
              let documentID = name.split(separator: "/").last else {
            throw CommunityError.badResponse
        }
        return String(documentID)
    }

    /// Deletes one of your shared scans.
    @MainActor
    func remove(documentID: String) async throws {
        guard isConfigured else { throw CommunityError.notConfigured }
        let auth = try await validToken()
        guard let url = URL(string: documentsBase + "/" + AppConfig.communityCollection + "/" + documentID) else {
            throw CommunityError.badResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        _ = try await send(request)
    }

    // MARK: Loading

    @MainActor
    func load(speciesID: String, sample: Bool) async {
        indexLink = nil
        if sample {
            scans = SampleCommunityData.scans(speciesID: speciesID)
            usingSampleData = true
            loadedSpeciesID = speciesID
            lastLoaded = Date()
            loadState = .loaded
            return
        }
        usingSampleData = false
        guard isConfigured else {
            scans = []
            loadState = .idle
            return
        }
        loadState = .loading
        do {
            let object = try await runQuery(speciesID: speciesID, limit: 1000)
            var result: [CommunityScan] = []
            for item in (object as? [[String: Any]]) ?? [] {
                guard let document = item["document"] as? [String: Any],
                      let scan = CommunityService.parse(document: document) else { continue }
                result.append(scan)
            }
            scans = result
            loadedSpeciesID = speciesID
            lastLoaded = Date()
            loadState = .loaded
        } catch CommunityError.server(let message) {
            if message.lowercased().contains("index") {
                indexLink = CommunityService.firstLink(in: message)
            }
            loadState = .failed(message)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Checks sign-in and a read; returns a message for Settings.
    @MainActor
    func testConnection() async -> String {
        guard isConfigured else { return "Add your Firebase project ID and Web API key first." }
        do {
            let auth = try await validToken()
            _ = try await runQuery(speciesID: "blue_crab", limit: 1)
            return "Connected. Signed in anonymously as \(auth.uid.prefix(6))… and reads work."
        } catch {
            return "Connection failed: \(error.localizedDescription)"
        }
    }

    private func runQuery(speciesID: String, limit: Int) async throws -> Any {
        guard let url = URL(string: documentsBase + ":runQuery") else { throw CommunityError.notConfigured }
        let speciesField: [String: Any] = ["fieldPath": "species"]
        let speciesValue: [String: Any] = ["stringValue": speciesID]
        let fieldFilter: [String: Any] = ["field": speciesField, "op": "EQUAL", "value": speciesValue]
        let takenAtField: [String: Any] = ["fieldPath": "takenAt"]
        let order: [String: Any] = ["field": takenAtField, "direction": "DESCENDING"]
        let collection: [String: Any] = ["collectionId": AppConfig.communityCollection]
        var structuredQuery: [String: Any] = [:]
        structuredQuery["from"] = [collection]
        structuredQuery["where"] = ["fieldFilter": fieldFilter]
        structuredQuery["orderBy"] = [order]
        structuredQuery["limit"] = limit
        let body: [String: Any] = ["structuredQuery": structuredQuery]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = try? await validToken() {
            request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    // MARK: Anonymous auth (Firebase Auth REST)

    private func validToken() async throws -> (token: String, uid: String) {
        if let idToken, let userID, tokenExpiry > Date().addingTimeInterval(60) {
            return (idToken, userID)
        }
        if let refresh = Keychain.get(refreshKeychainKey),
           let refreshed = try? await refreshToken(refresh) {
            return refreshed
        }
        return try await signUpAnonymously()
    }

    private func signUpAnonymously() async throws -> (token: String, uid: String) {
        guard let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(encodedKey)") else {
            throw CommunityError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["returnSecureToken": true])
        let object = try await send(request)
        guard let json = object as? [String: Any],
              let token = json["idToken"] as? String,
              let refresh = json["refreshToken"] as? String,
              let uid = json["localId"] as? String else {
            throw CommunityError.badResponse
        }
        let lifetime = Double(json["expiresIn"] as? String ?? "3600") ?? 3600
        remember(token: token, refresh: refresh, uid: uid, lifetime: lifetime)
        return (token, uid)
    }

    private func refreshToken(_ refresh: String) async throws -> (token: String, uid: String) {
        guard let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(encodedKey)") else {
            throw CommunityError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let encoded = refresh.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? refresh
        request.httpBody = Data("grant_type=refresh_token&refresh_token=\(encoded)".utf8)
        let object = try await send(request)
        guard let json = object as? [String: Any],
              let token = json["id_token"] as? String,
              let newRefresh = json["refresh_token"] as? String,
              let uid = json["user_id"] as? String else {
            throw CommunityError.badResponse
        }
        let lifetime = Double(json["expires_in"] as? String ?? "3600") ?? 3600
        remember(token: token, refresh: newRefresh, uid: uid, lifetime: lifetime)
        return (token, uid)
    }

    private func remember(token: String, refresh: String, uid: String, lifetime: Double) {
        idToken = token
        userID = uid
        tokenExpiry = Date().addingTimeInterval(lifetime)
        Keychain.set(refresh, for: refreshKeychainKey)
    }

    // MARK: Firestore value helpers

    private static func stringValue(_ value: String) -> [String: Any] {
        ["stringValue": value]
    }

    private static func doubleValue(_ value: Double) -> [String: Any] {
        ["doubleValue": value]
    }

    private static func timestampValue(_ date: Date) -> [String: Any] {
        ["timestampValue": isoFormatter.string(from: date)]
    }

    // MARK: Networking helpers

    private func send(_ request: URLRequest) async throws -> Any {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object: Any = (try? JSONSerialization.jsonObject(with: data)) ?? [String: Any]()
        guard (200..<300).contains(status) else {
            throw CommunityError.server(CommunityService.errorMessage(from: object) ?? "HTTP \(status)")
        }
        return object
    }

    static func errorMessage(from object: Any?) -> String? {
        if let dict = object as? [String: Any],
           let error = dict["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        if let array = object as? [[String: Any]],
           let error = array.first?["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }

    static func firstLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func parse(document: [String: Any]) -> CommunityScan? {
        guard let name = document["name"] as? String,
              let fields = document["fields"] as? [String: Any] else { return nil }

        func string(_ key: String) -> String {
            (fields[key] as? [String: Any])?["stringValue"] as? String ?? ""
        }
        func double(_ key: String) -> Double? {
            guard let value = fields[key] as? [String: Any] else { return nil }
            if let number = value["doubleValue"] as? Double { return number }
            if let text = value["integerValue"] as? String { return Double(text) }
            if let number = value["integerValue"] as? Double { return number }
            return nil
        }

        guard let size = double("sizeIn"), size > 0 else { return nil }
        var taken = Date.distantPast
        if let text = (fields["takenAt"] as? [String: Any])?["timestampValue"] as? String {
            taken = isoFormatter.date(from: text) ?? isoFractionalFormatter.date(from: text) ?? Date.distantPast
        }
        return CommunityScan(
            id: String(name.split(separator: "/").last ?? Substring(name)),
            speciesID: string("species"),
            sizeInches: size,
            method: string("method"),
            sex: string("sex"),
            shell: string("shell"),
            verdict: string("verdict"),
            stateCode: string("state"),
            county: string("county"),
            waterBody: string("waterBody"),
            latitude: double("lat"),
            longitude: double("lon"),
            takenAt: taken,
            uid: string("uid"))
    }
}
