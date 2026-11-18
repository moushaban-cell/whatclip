import Foundation

/// The interface languages. English is the default; the choice is made in the first-run tour and kept in Settings.
/// Strings not yet translated fall back to English, so every language always shows the whole interface.
@MainActor
enum Lang {
    static var current = "en"

    static let names: [(code: String, name: String)] = [
        ("en", "English"), ("es", "Español"), ("fr", "Français"), ("de", "Deutsch"), ("ar", "العربية"),
    ]

    /// Text for a key in the current language, or English when that language has no translation yet.
    static func t(_ key: String) -> String {
        table[current]?[key] ?? table["en"]?[key] ?? key
    }

    static let table: [String: [String: String]] = [
        "en": [
            "tour.language.title": "Choose your language",
            "tour.language.body": "WhatClip starts in English. Pick another language now, or change it later in Settings.",
            "menu.openPicker": "Open clipboard picker",
            "menu.openHistory": "Open history window",
            "menu.settings": "Settings…",
            "menu.quit": "Quit WhatClip",
        ],
        "es": [
            "tour.language.title": "Elige tu idioma",
            "tour.language.body": "WhatClip empieza en inglés. Elige otro idioma ahora o cámbialo después en Ajustes.",
            "menu.openPicker": "Abrir el selector del portapapeles",
            "menu.openHistory": "Abrir la ventana del historial",
            "menu.settings": "Ajustes…",
            "menu.quit": "Salir de WhatClip",
        ],
        "fr": [
            "tour.language.title": "Choisissez votre langue",
            "tour.language.body": "WhatClip démarre en anglais. Choisissez une autre langue maintenant, ou changez-la plus tard dans Réglages.",
            "menu.openPicker": "Ouvrir le sélecteur du presse-papiers",
            "menu.openHistory": "Ouvrir la fenêtre de l’historique",
            "menu.settings": "Réglages…",
            "menu.quit": "Quitter WhatClip",
        ],
        "de": [
            "tour.language.title": "Sprache wählen",
            "tour.language.body": "WhatClip startet auf Englisch. Wähle jetzt eine andere Sprache oder ändere sie später in den Einstellungen.",
            "menu.openPicker": "Zwischenablage-Auswahl öffnen",
            "menu.openHistory": "Verlaufsfenster öffnen",
            "menu.settings": "Einstellungen…",
            "menu.quit": "WhatClip beenden",
        ],
        "ar": [
            "tour.language.title": "اختر لغتك",
            "tour.language.body": "يبدأ WhatClip بالإنجليزية. اختر لغة أخرى الآن، أو غيّرها لاحقاً من الإعدادات.",
            "menu.openPicker": "فتح منتقي الحافظة",
            "menu.openHistory": "فتح نافذة السجل",
            "menu.settings": "الإعدادات…",
            "menu.quit": "إنهاء WhatClip",
        ],
    ]
}
