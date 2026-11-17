import Foundation

/// Blazify Project (C) 2026
/// Licensed under GPL-3.0

/// Festival touches on the Home logo. A festival shows only in the countries that celebrate
/// it (where it is a public holiday; Halloween and the global days everywhere), from a week
/// before it until two days after: what a country's own calendar celebrates, never a guess
/// about the person holding the phone. Everything is decided on the phone; nothing about it
/// is sent anywhere. The same festivals, days and rules as the Android app.
///
/// Plain Foundation only, so it can be compiled and its days tested on a machine with no Xcode.

/// A calendar day with no time and no time zone, so a festival starts at midnight wherever
/// the phone is, and two days compare by counting.
struct FestivalDay: Comparable, Hashable {
    /// Days since 1 January 1970.
    let number: Int

    init(_ year: Int, _ month: Int, _ day: Int) {
        // Howard Hinnant's days-from-civil: exact for every Gregorian date, no calendar needed.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        number = era * 146_097 + doe - 719_468
    }

    private init(number: Int) { self.number = number }

    func adding(days: Int) -> FestivalDay { FestivalDay(number: number + days) }

    /// Today on the phone's own calendar and clock.
    static var today: FestivalDay {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: .current, from: Date())
        return FestivalDay(parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    static func < (a: FestivalDay, b: FestivalDay) -> Bool { a.number < b.number }
}

/// A festival's days, first and last included.
struct FestivalDays {
    let first: FestivalDay
    let last: FestivalDay

    init(_ first: FestivalDay, _ last: FestivalDay) {
        self.first = first
        self.last = last
    }
}

enum Festival: String, CaseIterable, Identifiable {
    // The raw values are stable ids, the same as Android's; never rename them.
    // Tihar in Nepal, Diwali or Deepavali elsewhere: one festival of lights, with its local name.
    case diwali = "diwali"
    // Not a public holiday anywhere, but kept in cities all over the world, so it shows everywhere.
    // Where Diwali falls on the same days, as in 2027, Diwali shows instead.
    case halloween = "halloween"
    case christmas = "christmas"
    case newYear = "new_year"
    case musicDay = "music_day"
    // The festivals below follow lunar calendars. Their days are added from each country's
    // official calendar once it is published; until then they never show by themselves.
    case holi = "holi"
    case dashain = "dashain"
    case lunarNewYear = "lunar_new_year"
    case eidAlFitr = "eid_al_fitr"
    case eidAlAdha = "eid_al_adha"

    var id: String { rawValue }

    /// The celebration starts this many days before a festival's first day…
    static let daysBefore = 7
    /// …and lasts this many days after its last.
    static let daysAfter = 2

    /// Where it is a public holiday, as ISO country codes; empty means everywhere.
    var countries: Set<String> {
        switch self {
        case .diwali: ["NP", "IN", "MY", "SG", "LK", "MU", "FJ", "TT", "GY", "SR"]
        case .holi: ["IN", "NP"]
        case .dashain: ["NP"]
        case .lunarNewYear: ["CN", "TW", "HK", "MO", "SG", "MY", "VN", "KR", "BN"]
        case .eidAlFitr, .eidAlAdha: Self.eidCountries
        case .halloween, .christmas, .newYear, .musicDay: []
        }
    }

    /// With `countries` empty, the countries where it is not a public holiday.
    var notIn: Set<String> {
        switch self {
        case .christmas: [
            "CN", "JP", "TW", "TH", "VN", "KH", "LA", "MN", "BT", "MV", "AF", "IR", "SA", "AE", "QA",
            "KW", "BH", "OM", "YE", "TR", "IL", "LY", "MA", "TN", "MR", "SO", "DZ", "KP",
            // Orthodox Christmas on 7 January, with no holiday on 25 December: New Year shows there.
            "RU", "RS", "ME", "MK", "GE", "AM", "KZ", "KG", "UZ", "TJ", "TM", "AZ", "EG", "ET", "ER",
        ]
        default: []
        }
    }

    /// Its days. Nepal keeps Kag Tihar to Bhai Tika (per the Nepal Calendar Determination
    /// Committee), elsewhere Dhanteras to Bhai Dooj; the two fall within a day of each other,
    /// so one span covers both.
    var days: [FestivalDays] {
        switch self {
        case .diwali: [
            FestivalDays(FestivalDay(2026, 11, 6), FestivalDay(2026, 11, 11)),
            FestivalDays(FestivalDay(2027, 10, 27), FestivalDay(2027, 10, 31)),
        ]
        case .halloween: [
            FestivalDays(FestivalDay(2027, 10, 31), FestivalDay(2027, 10, 31)),
            FestivalDays(FestivalDay(2028, 10, 31), FestivalDay(2028, 10, 31)),
        ]
        case .christmas: [
            FestivalDays(FestivalDay(2026, 12, 24), FestivalDay(2026, 12, 26)),
            FestivalDays(FestivalDay(2027, 12, 24), FestivalDay(2027, 12, 26)),
        ]
        case .newYear: [
            FestivalDays(FestivalDay(2026, 12, 31), FestivalDay(2027, 1, 1)),
            FestivalDays(FestivalDay(2027, 12, 31), FestivalDay(2028, 1, 1)),
        ]
        case .musicDay: [
            FestivalDays(FestivalDay(2027, 6, 21), FestivalDay(2027, 6, 21)),
            FestivalDays(FestivalDay(2028, 6, 21), FestivalDay(2028, 6, 21)),
        ]
        case .holi, .dashain, .lunarNewYear, .eidAlFitr, .eidAlAdha: []
        }
    }

    /// Its greeting in English, which is also its translation key.
    var greeting: String {
        switch self {
        case .diwali: "Happy Diwali"
        case .halloween: "Happy Halloween"
        case .christmas: "Merry Christmas"
        case .newYear: "Happy New Year"
        case .musicDay: "Happy World Music Day"
        case .holi: "Happy Holi"
        case .dashain: "Happy Dashain"
        case .lunarNewYear: "Happy Lunar New Year"
        case .eidAlFitr, .eidAlAdha: "Eid Mubarak"
        }
    }

    /// Its greeting where it is celebrated: Diwali is Tihar in Nepal.
    func greeting(in country: String?) -> String {
        if self == .diwali, country?.uppercased() == "NP" { return "Happy Tihar" }
        return greeting
    }

    /// The festival for `country` on `date`, if any: from a week before it until two days after.
    /// When two overlap, as Christmas and New Year do, the one nearer to `date` shows, and on a
    /// tie the one still to come, so Christmas hands over to New Year once it is past.
    static func on(_ date: FestivalDay, country: String?) -> Festival? {
        guard let code = country?.uppercased(), !code.isEmpty else { return nil }
        var best: (festival: Festival, distance: Int, past: Int)?
        for festival in allCases {
            let here = festival.countries.isEmpty ? !festival.notIn.contains(code) : festival.countries.contains(code)
            guard here else { continue }
            for span in festival.days {
                guard date >= span.first.adding(days: -daysBefore), date <= span.last.adding(days: daysAfter) else { continue }
                let distance = date < span.first ? span.first.number - date.number
                    : date > span.last ? date.number - span.last.number : 0
                let past = date < span.first ? 0 : 1
                // The first of equals wins, as Android's minWith keeps the first smallest.
                if let b = best, (b.distance, b.past) <= (distance, past) { continue }
                best = (festival, distance, past)
            }
        }
        return best?.festival
    }

    /// Where both Eids are public holidays: Muslim-majority countries and South Asia.
    private static let eidCountries: Set<String> = [
        "SA", "AE", "QA", "KW", "BH", "OM", "YE", "JO", "IQ", "SY", "LB", "PS", "EG", "LY", "TN", "DZ", "MA",
        "MR", "SD", "SO", "DJ", "TR", "AZ", "IR", "AF", "PK", "BD", "IN", "MV", "MY", "ID", "BN", "SN", "ML",
        "NE", "TD", "GM", "GN", "SL", "NG", "KZ", "KG", "TJ", "TM", "UZ", "AL", "BA", "XK", "LK",
    ]
}

/// The country the festivals follow, read on the phone and never sent anywhere: the one chosen
/// in Settings › Content, else the phone's own region.
func festivalCountry() -> String? {
    if let chosen = UserDefaults.standard.string(forKey: "contentCountry")?.trimmingCharacters(in: .whitespaces),
       chosen.count == 2 {
        return chosen.uppercased()
    }
    guard let region = Locale.current.region?.identifier, region.count == 2 else { return nil }
    return region.uppercased()
}
