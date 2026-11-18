import Foundation

/// The interface languages: English by default, then the ten most-spoken languages in the world.
/// The choice is made on the first page of the welcome tour and kept in Settings; it applies the next time WhatClip starts.
/// Strings that are not translated yet fall back to English, so every language always shows the whole interface.
@MainActor
enum Lang {
    static var current = "en"

    /// Code, and the language's own name for it.
    static let names: [(code: String, name: String)] = [
        ("en", "English"), ("zh-Hans", "简体中文"), ("hi", "हिन्दी"), ("es", "Español"), ("fr", "Français"),
        ("ar", "العربية"), ("bn", "বাংলা"), ("pt", "Português"), ("ru", "Русский"), ("ja", "日本語"), ("de", "Deutsch"),
    ]

    /// Arabic reads right to left. Set when the app starts, so the system layout follows the language.
    static var isRightToLeft: Bool { current == "ar" }

    static func t(_ key: String) -> String {
        table[current]?[key] ?? table["en"]?[key] ?? key
    }

    static let table: [String: [String: String]] = [
        "en": [
            "tour.language.title": "Choose your language",
            "tour.language.body": "WhatClip starts in English. Pick another language now, or change it later in Settings.",
            "menu.openPicker": "Open clipboard picker", "menu.openHistory": "Open history window",
            "menu.settings": "Settings…", "menu.quit": "Quit WhatClip",
        ],
        "zh-Hans": [
            "tour.language.title": "选择语言",
            "tour.language.body": "WhatClip 默认使用英语。现在可以选择其他语言，也可以以后在“设置”中更改。",
            "menu.openPicker": "打开剪贴板选择器", "menu.openHistory": "打开历史窗口",
            "menu.settings": "设置…", "menu.quit": "退出 WhatClip",
        ],
        "hi": [
            "tour.language.title": "अपनी भाषा चुनें",
            "tour.language.body": "WhatClip अंग्रेज़ी में शुरू होता है। अभी कोई दूसरी भाषा चुनें, या बाद में सेटिंग्स में बदलें।",
            "menu.openPicker": "क्लिपबोर्ड चयनकर्ता खोलें", "menu.openHistory": "इतिहास विंडो खोलें",
            "menu.settings": "सेटिंग्स…", "menu.quit": "WhatClip बंद करें",
        ],
        "es": [
            "tour.language.title": "Elige tu idioma",
            "tour.language.body": "WhatClip empieza en inglés. Elige otro idioma ahora o cámbialo después en Ajustes.",
            "menu.openPicker": "Abrir el selector del portapapeles", "menu.openHistory": "Abrir la ventana del historial",
            "menu.settings": "Ajustes…", "menu.quit": "Salir de WhatClip",
        ],
        "fr": [
            "tour.language.title": "Choisissez votre langue",
            "tour.language.body": "WhatClip démarre en anglais. Choisissez une autre langue maintenant, ou changez-la plus tard dans Réglages.",
            "menu.openPicker": "Ouvrir le sélecteur du presse-papiers", "menu.openHistory": "Ouvrir la fenêtre de l’historique",
            "menu.settings": "Réglages…", "menu.quit": "Quitter WhatClip",
        ],
        "ar": [
            "tour.language.title": "اختر لغتك",
            "tour.language.body": "يبدأ WhatClip بالإنجليزية. اختر لغة أخرى الآن، أو غيّرها لاحقاً من الإعدادات.",
            "menu.openPicker": "فتح منتقي الحافظة", "menu.openHistory": "فتح نافذة السجل",
            "menu.settings": "الإعدادات…", "menu.quit": "إنهاء WhatClip",
        ],
        "bn": [
            "tour.language.title": "আপনার ভাষা বেছে নিন",
            "tour.language.body": "WhatClip ইংরেজিতে শুরু হয়। এখনই অন্য একটি ভাষা বেছে নিন, অথবা পরে সেটিংসে বদলান।",
            "menu.openPicker": "ক্লিপবোর্ড পিকার খুলুন", "menu.openHistory": "ইতিহাস উইন্ডো খুলুন",
            "menu.settings": "সেটিংস…", "menu.quit": "WhatClip বন্ধ করুন",
        ],
        "pt": [
            "tour.language.title": "Escolha o seu idioma",
            "tour.language.body": "O WhatClip começa em inglês. Escolha outro idioma agora ou mude depois nas Definições.",
            "menu.openPicker": "Abrir o seletor da área de transferência", "menu.openHistory": "Abrir a janela do histórico",
            "menu.settings": "Definições…", "menu.quit": "Sair do WhatClip",
        ],
        "ru": [
            "tour.language.title": "Выберите язык",
            "tour.language.body": "WhatClip запускается на английском. Выберите другой язык сейчас или измените его позже в настройках.",
            "menu.openPicker": "Открыть выбор буфера обмена", "menu.openHistory": "Открыть окно истории",
            "menu.settings": "Настройки…", "menu.quit": "Завершить WhatClip",
        ],
        "ja": [
            "tour.language.title": "言語を選択",
            "tour.language.body": "WhatClip は英語で始まります。今すぐ別の言語を選ぶか、後で設定から変更できます。",
            "menu.openPicker": "クリップボードのピッカーを開く", "menu.openHistory": "履歴ウインドウを開く",
            "menu.settings": "設定…", "menu.quit": "WhatClip を終了",
        ],
        "de": [
            "tour.language.title": "Sprache wählen",
            "tour.language.body": "WhatClip startet auf Englisch. Wähle jetzt eine andere Sprache oder ändere sie später in den Einstellungen.",
            "menu.openPicker": "Zwischenablage-Auswahl öffnen", "menu.openHistory": "Verlaufsfenster öffnen",
            "menu.settings": "Einstellungen…", "menu.quit": "WhatClip beenden",
        ],
    ]
}
