import Foundation

struct LyricsResult: Sendable {
    let lines: [LyricsLine]
    let synchronized: Bool
}
struct LyricsService: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)
    let transport: Transport
    init(transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }) { self.transport = transport }
    func load(enabled: Bool, title: String, artist: String, album: String) async throws -> LyricsResult? {
        guard enabled, !title.isEmpty, !artist.isEmpty else { return nil }
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist), URLQueryItem(name: "album_name", value: album)]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url); request.timeoutInterval = 10
        request.setValue("AltTabber/0.5.4", forHTTPHeaderField: "User-Agent")
        let (data, status) = try await transport(request)
        guard status == 200 else { throw URLError(.resourceUnavailable) }
        struct Response: Decodable { let syncedLyrics: String?; let plainLyrics: String? }
        let value = try JSONDecoder().decode(Response.self, from: data)
        let synchronized = !(value.syncedLyrics ?? "").isEmpty
        return LyricsResult(lines: LyricsParser.parse(synchronized ? value.syncedLyrics! : value.plainLyrics ?? "", synchronized: synchronized), synchronized: synchronized)
    }
}

enum CalendarListing {
    static func filter(_ events: [CalendarEntry], authorized: Bool, now: Date, exclusions: [String]) -> [CalendarEntry] {
        guard authorized else { return [] }
        let calendar = Calendar.current
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
        return events.filter {
            $0.end >= now && $0.start < endOfDay && !exclusions.contains($0.calendar) && !exclusions.contains($0.calendarID)
        }.sorted { $0.start < $1.start }
    }
}
