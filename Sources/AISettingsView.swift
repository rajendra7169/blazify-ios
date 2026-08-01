import SwiftUI

/// Settings → Lyrics → AI translation.
struct AISettingsView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var prefs = AIPrefs.shared

    @State private var showProvider = false
    @State private var showMode = false
    @State private var showFormality = false
    @State private var showLanguage = false
    @State private var showKey = false
    @State private var showPrompt = false
    @State private var keyDraft = ""

    var body: some View {
        SettingsPage(title: "AI translation") {
            SettingsGroup(title: "Translation") {
                SettingsToggle(symbol: "character.book.closed", title: "Translate lyrics",
                               subtitle: "Show a translation under each line",
                               isOn: $prefs.enabled)
            }

            if prefs.enabled {
                SettingsGroup(title: "Service") {
                    SettingsLink(symbol: "cpu", title: "Provider",
                                 subtitle: prefs.provider.title) { showProvider = true }
                    SettingsDivider()
                    SettingsLink(symbol: "key", title: "API key",
                                 subtitle: prefs.apiKey.isEmpty
                                     ? "Not set — get one at \(prefs.provider.keyPage)"
                                     : "Saved in the Keychain") {
                        keyDraft = ""
                        showKey = true
                    }
                    if !prefs.provider.isDeepL {
                        SettingsDivider()
                        SettingsLink(symbol: "shippingbox", title: "Model",
                                     subtitle: prefs.model) { showPrompt = false; showModel = true }
                    }
                }

                SettingsGroup(title: "Output") {
                    SettingsLink(symbol: "globe", title: "Translate into",
                                 subtitle: ContentPrefs.name(ofLanguage: prefs.targetLanguage)) {
                        showLanguage = true
                    }
                    if prefs.provider.isDeepL {
                        SettingsDivider()
                        SettingsLink(symbol: "text.quote", title: "Formality",
                                     subtitle: prefs.formality.title) { showFormality = true }
                    } else {
                        SettingsDivider()
                        SettingsLink(symbol: "arrow.left.arrow.right", title: "Mode",
                                     subtitle: prefs.mode.title) { showMode = true }
                        SettingsDivider()
                        SettingsLink(symbol: "text.alignleft", title: "System prompt",
                                     subtitle: "How the model is told to translate") {
                            showPrompt = true
                        }
                    }
                }
            }

            Text("Your key is stored in the iOS Keychain and used only to "
                 + "translate lyrics you're looking at. Blazify has no server: "
                 + "requests go straight from this phone to the provider you pick. "
                 + "With no key entered, nothing is ever sent.")
                .font(.blaze(12))
                .foregroundStyle(palette.onSurfaceVariant)
                .padding(.horizontal, 6)
        }
        .sheet(isPresented: $showProvider) {
            EnumPickerSheet(title: "Provider", options: AIProvider.allCases,
                            label: { "\($0.title) — \($0.keyPage)" },
                            selection: $prefs.provider)
        }
        .sheet(isPresented: $showMode) {
            EnumPickerSheet(title: "Mode", options: TranslationMode.allCases,
                            label: { "\($0.title) — \($0.blurb)" }, selection: $prefs.mode)
        }
        .sheet(isPresented: $showFormality) {
            EnumPickerSheet(title: "Formality", options: DeepLFormality.allCases,
                            label: \.title, selection: $prefs.formality)
        }
        .sheet(isPresented: $showLanguage) {
            ValuePickerSheet(title: "Translate into",
                             options: ContentPrefs.languages.map(\.code),
                             label: ContentPrefs.name(ofLanguage:),
                             selection: $prefs.targetLanguage)
        }
        .sheet(isPresented: $showKey) { keySheet }
        .sheet(isPresented: $showModel) { modelSheet }
        .sheet(isPresented: $showPrompt) { promptSheet }
    }

    @State private var showModel = false
    @State private var modelDraft = ""

    private var keySheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("API key", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !prefs.apiKey.isEmpty {
                        Button("Remove the saved key", role: .destructive) {
                            prefs.apiKey = ""
                            showKey = false
                        }
                    }
                } header: {
                    Text(prefs.provider.title)
                } footer: {
                    Text("Create one at \(prefs.provider.keyPage)")
                }
                .listRowBackground(palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("API key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { prefs.apiKey = keyDraft; showKey = false }
                        .tint(palette.accent)
                        .disabled(keyDraft.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var modelSheet: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    TextField(prefs.provider.defaultModel, text: $modelDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Use the default") { modelDraft = prefs.provider.defaultModel }
                }
                .listRowBackground(palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { modelDraft = prefs.model }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { prefs.model = modelDraft; showModel = false }
                        .tint(palette.accent)
                }
            }
        }
        .presentationDetents([.medium])
    }

    @State private var promptDraft = ""

    private var promptSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $promptDraft)
                    .font(.blaze(14))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button("Reset to the default") { promptDraft = AIPrefs.defaultPrompt }
                    .font(.blaze(14, .semibold))
                    .foregroundStyle(palette.accent)
            }
            .padding(16)
            .background(palette.scaffold.ignoresSafeArea())
            .navigationTitle("System prompt")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { promptDraft = prefs.systemPrompt }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { prefs.systemPrompt = promptDraft; showPrompt = false }
                        .tint(palette.accent)
                }
            }
        }
    }
}
