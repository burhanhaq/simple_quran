import Foundation

/// Other names people use for a surah. Spelling variants (Taha / Taa-Haa, Yasin / Yaseen) need no
/// entry here because `SearchKey` folds them; this list is for names that are genuinely different.
nonisolated enum SurahAliases {
    static func aliases(for number: Int) -> [String] { table[number] ?? [] }

    private static let table: [Int: [String]] = [
        1: ["Umm al-Kitab", "Umm al-Quran", "Al-Hamd"],
        3: ["Al Imran", "Ali Imran"],
        9: ["Bara'ah", "Baraat"],
        10: ["Jonah"],
        17: ["Bani Isra'il", "Bani Israel"],
        40: ["Al-Mu'min", "Momin"],
        41: ["Ha Mim Sajdah"],
        45: ["Jasiya"],
        47: ["Al-Qital"],
        51: ["Az-Zariyat"],
        55: ["Rehman"],
        58: ["Al-Mujadalah"],
        62: ["Jumah"],
        67: ["Tabarak"],
        68: ["Nun"],
        74: ["Al-Muddassir"],
        76: ["Ad-Dahr", "Hal Ata"],
        78: ["Amma"],
        83: ["At-Tatfif"],
        87: ["Sabbih"],
        93: ["Az-Zuha"],
        94: ["Al-Inshirah", "Alam Nashrah"],
        96: ["Iqra"],
        98: ["Lam Yakun"],
        99: ["Az-Zilzal"],
        102: ["At-Takasur"],
        108: ["Al-Kausar"],
        111: ["Al-Lahab", "Tabbat"],
        112: ["At-Tawhid", "Qul Huwallah"]
    ]
}

/// The traditional names of each juz, taken from its opening words, as used in hifz circles
/// (often called para or sipara).
nonisolated enum JuzNames {
    static func names(for number: Int) -> [String] { table[number] ?? [] }

    private static let table: [Int: [String]] = [
        1: ["Alif Lam Mim"],
        2: ["Sayaqul"],
        3: ["Tilka r-Rusul", "Tilkal Rusul"],
        4: ["Lan Tanalu"],
        5: ["Wal Muhsanat"],
        6: ["La Yuhibbullah"],
        7: ["Wa Idha Sami'u"],
        8: ["Wa Law Annana"],
        9: ["Qal al-Mala'u"],
        10: ["Wa A'lamu"],
        11: ["Ya'tadhirun"],
        12: ["Wa Ma Min Dabbah"],
        13: ["Wa Ma Ubarri'u"],
        14: ["Rubama"],
        15: ["Subhan alladhi"],
        16: ["Qal alam"],
        17: ["Iqtaraba"],
        18: ["Qad Aflaha"],
        19: ["Wa Qal alladhina"],
        20: ["Amman Khalaq"],
        21: ["Utlu Ma Uhiya"],
        22: ["Wa Man Yaqnut"],
        23: ["Wa Mali"],
        24: ["Fa Man Azlam"],
        25: ["Ilayhi Yuraddu"],
        26: ["Ha Mim"],
        27: ["Qala Fa Ma Khatbukum"],
        28: ["Qad Sami Allah"],
        29: ["Tabarakalladhi"],
        30: ["Amma"]
    ]
}

/// Well-known passages people search for by name rather than by reference.
nonisolated struct NamedPassage: Sendable {
    var names: [String]
    var surah: Int
    var startAyah: Int
    var endAyah: Int

    static let all: [NamedPassage] = [
        NamedPassage(names: ["Ayat al-Kursi", "Ayatul Kursi", "Kursi", "Throne Verse", "آية الكرسي"], surah: 2, startAyah: 255, endAyah: 255),
        NamedPassage(names: ["Amana ar-Rasul", "Amanar Rasul"], surah: 2, startAyah: 285, endAyah: 286),
        NamedPassage(names: ["Ayat an-Nur", "Light Verse"], surah: 24, startAyah: 35, endAyah: 35)
    ]
}
