import Combine
import SwiftUI

/// The translation services Android's AI settings offer. Everything is
/// bring-your-own-key: nothing leaves the phone unless you've entered one.
enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openAI, claude, gemini, deepL, mistral, openRouter, perplexity, xAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: return String(localized: "OpenAI")
        case .claude: return String(localized: "Claude")
        case .gemini: return String(localized: "Gemini")
        case .deepL: return String(localized: "DeepL")
        case .mistral: return String(localized: "Mistral")
        case .openRouter: return String(localized: "OpenRouter")
        case .perplexity: return String(localized: "Perplexity")
        case .xAI: return String(localized: "xAI")
        }
    }

    var keyPage: String {
        switch self {
        case .openAI: return "platform.openai.com/api-keys"
        case .claude: return "console.anthropic.com"
        case .gemini: return "aistudio.google.com/apikey"
        case .deepL: return "deepl.com/pro-api"
        case .mistral: return "console.mistral.ai"
        case .openRouter: return "openrouter.ai/keys"
        case .perplexity: return "perplexity.ai/settings/api"
        case .xAI: return "console.x.ai"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .claude: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .deepL: return "https://api-free.deepl.com/v2"
        case .mistral: return "https://api.mistral.ai/v1"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .perplexity: return "https://api.perplexity.ai"
        case .xAI: return "https://api.x.ai/v1"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .claude: return "claude-sonnet-4-5"
        case .gemini: return "gemini-2.0-flash"
        case .deepL: return ""            // DeepL has no model to choose
        case .mistral: return "mistral-small-latest"
        case .openRouter: return "openai/gpt-4o-mini"
        case .perplexity: return "sonar"
        case .xAI: return "grok-3-mini"
        }
    }

    /// DeepL is a translation API, not a chat one, so it takes a different path
    /// and offers formality instead of a prompt.
    var isDeepL: Bool { self == .deepL }
}

enum TranslationMode: String, CaseIterable, Identifiable {
    case literal, transcribed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .literal: return String(localized: "Literal")
        case .transcribed: return String(localized: "Transcribed")
        }
    }
    var blurb: String {
        switch self {
        case .literal: return String(localized: "Translate the meaning of each line")
        case .transcribed: return String(localized: "Write the sounds in your own script instead")
        }
    }
}

enum DeepLFormality: String, CaseIterable, Identifiable {
    case `default`, less, more
    var id: String { rawValue }
    var title: String {
        switch self {
        case .default: return String(localized: "Default")
        case .less: return String(localized: "Less formal")
        case .more: return String(localized: "More formal")
        }
    }
}

/// Settings → Lyrics → AI translation, ported from `AiSettings.kt`.
final class AIPrefs: ObservableObject {
    static let shared = AIPrefs()

    @Published var enabled: Bool { didSet { save(enabled, "aiTranslationEnabled") } }
    @Published var provider: AIProvider {
        didSet {
            save(provider.rawValue, "aiProvider")
            // Base URL and model belong to the provider, so follow it unless
            // they've been deliberately changed.
            if baseURL.isEmpty || AIProvider.allCases.contains(where: { $0.defaultBaseURL == baseURL }) {
                baseURL = provider.defaultBaseURL
            }
            if model.isEmpty || AIProvider.allCases.contains(where: { $0.defaultModel == model }) {
                model = provider.defaultModel
            }
        }
    }
    @Published var baseURL: String { didSet { save(baseURL, "aiBaseUrl") } }
    @Published var model: String { didSet { save(model, "aiModel") } }
    @Published var targetLanguage: String { didSet { save(targetLanguage, "aiTargetLanguage") } }
    @Published var mode: TranslationMode { didSet { save(mode.rawValue, "aiTranslationMode") } }
    @Published var formality: DeepLFormality { didSet { save(formality.rawValue, "aiDeeplFormality") } }
    @Published var systemPrompt: String { didSet { save(systemPrompt, "aiSystemPrompt") } }

    /// The key never touches UserDefaults — same treatment as the YouTube cookie.
    var apiKey: String {
        get { Keychain.get("aiApiKey") ?? "" }
        set { Keychain.set(newValue.isEmpty ? nil : newValue, for: "aiApiKey"); objectWillChange.send() }
    }

    var isConfigured: Bool { enabled && !apiKey.isEmpty }

    static let defaultPrompt = """
        You are translating song lyrics. Return exactly the same number of lines \
        as the input, one translated line per input line, with no numbering, \
        commentary or blank lines. Keep the tone and imagery of the original. \
        If a line is unclear, give your best approximation rather than skipping it.
        """

    private init() {
        let d = UserDefaults.standard
        enabled = d.object(forKey: "aiTranslationEnabled") as? Bool ?? false
        let chosen = AIProvider(rawValue: d.string(forKey: "aiProvider") ?? "") ?? .openAI
        provider = chosen
        baseURL = d.string(forKey: "aiBaseUrl") ?? chosen.defaultBaseURL
        model = d.string(forKey: "aiModel") ?? chosen.defaultModel
        targetLanguage = d.string(forKey: "aiTargetLanguage")
            ?? (Locale.current.language.languageCode?.identifier ?? "en")
        mode = TranslationMode(rawValue: d.string(forKey: "aiTranslationMode") ?? "") ?? .literal
        formality = DeepLFormality(rawValue: d.string(forKey: "aiDeeplFormality") ?? "") ?? .default
        systemPrompt = d.string(forKey: "aiSystemPrompt") ?? Self.defaultPrompt
    }

    func resetPrompt() { systemPrompt = Self.defaultPrompt }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
