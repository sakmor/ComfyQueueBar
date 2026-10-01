import Foundation

let cases: [([String], String)] = [
    (["zh-TW"], "zh-Hant"), (["zh-HK"], "zh-Hant"), (["zh-MO"], "zh-Hant"),
    (["zh-Hans-TW"], "zh-Hans"), (["zh-Hant-CN"], "zh-Hant"),
    (["zh-CN"], "zh-Hans"), (["zh-SG"], "zh-Hans"), (["zh"], "zh-Hans"),
    (["ja-JP"], "ja"), (["en-GB", "ja"], "en"), (["fr", "ja"], "ja"),
    (["de"], "en"), ([], "en")
]
for (preferences, expected) in cases {
    precondition(L10n.resolve(preferences) == expected, "Language selection failed: \(preferences)")
}
for (key, values) in L10n.translations {
    precondition(values.count == 3, "Missing translations: \(key)")
    for value in values {
        precondition(!value.isEmpty)
        precondition(value.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count, "Placeholder mismatch: \(key)")
    }
}
let expected = ["en": "Connect", "zh-Hant": "連線", "zh-Hans": "连接", "ja": "接続"]
precondition(L10n.text("Connect") == expected[L10n.language])
precondition(L10n.text("%@ nodes", "24").contains("24"))
precondition(L10n.text("Move \"%@\" to the front of the waiting queue. The running job continues. This resubmits the job and changes its prompt ID.", "100% sample").contains("100% sample"))
precondition(L10n.text("Unknown key") == "Unknown key")
print("Localization passed: \(L10n.language), \(L10n.translations.count) keys")
