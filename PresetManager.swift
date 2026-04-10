import Foundation

@Observable
class PresetManager {
    private(set) var presets: [TrailPreset] = []
    var activePresetID: UUID?

    /// Snapshot taken when a preset is loaded or saved — used for dirty tracking
    private var cleanSnapshot: TrailPreset?

    private enum Keys {
        static let presets = "presets.list"
        static let activePresetID = "presets.activeID"
    }

    init() {
        loadFromDisk()
    }

    // MARK: - CRUD

    func saveNewPreset(name: String, from settings: TrailSettings) {
        let preset = TrailPreset(name: name, from: settings)
        presets.append(preset)
        activePresetID = preset.id
        cleanSnapshot = TrailPreset(name: "", from: settings)
        saveToDisk()
    }

    func updatePreset(id: UUID, from settings: TrailSettings) {
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        let updated = TrailPreset(
            id: presets[idx].id,
            name: presets[idx].name,
            createdAt: presets[idx].createdAt,
            updatedAt: Date(),
            isTrailVisible: settings.isTrailVisible,
            isRippleEnabled: settings.isRippleEnabled,
            maxWidth: settings.maxWidth,
            blueWidthMultiplier: settings.blueWidthMultiplier,
            movementThreshold: settings.movementThreshold,
            minimumVelocity: settings.minimumVelocity,
            redFadeTime: settings.redFadeTime,
            blueFadeTime: settings.blueFadeTime,
            redTrailR: settings.redTrailR,
            redTrailG: settings.redTrailG,
            redTrailB: settings.redTrailB,
            blueTrailR: settings.blueTrailR,
            blueTrailG: settings.blueTrailG,
            blueTrailB: settings.blueTrailB,
            blueOuterOpacity: settings.blueOuterOpacity,
            blueMiddleOpacity: settings.blueMiddleOpacity
        )
        presets[idx] = updated
        cleanSnapshot = TrailPreset(name: "", from: settings)
        saveToDisk()
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        if activePresetID == id {
            activePresetID = nil
            cleanSnapshot = nil
        }
        saveToDisk()
    }

    func renamePreset(id: UUID, to newName: String) {
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[idx].name = newName
        saveToDisk()
    }

    // MARK: - Apply

    func applyPreset(_ preset: TrailPreset, to settings: TrailSettings) {
        settings.apply(preset: preset)
        activePresetID = preset.id
        cleanSnapshot = TrailPreset(name: "", from: settings)
        saveToDisk()
    }

    // MARK: - Dirty Tracking

    func hasUnsavedChanges(relativeTo settings: TrailSettings) -> Bool {
        guard let clean = cleanSnapshot else { return false }
        let current = TrailPreset(name: "", from: settings)
        return !current.settingsMatch(clean)
    }

    func takeCleanSnapshot(from settings: TrailSettings) {
        cleanSnapshot = TrailPreset(name: "", from: settings)
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(presets) {
            UserDefaults.standard.set(data, forKey: Keys.presets)
        }
        if let id = activePresetID {
            UserDefaults.standard.set(id.uuidString, forKey: Keys.activePresetID)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.activePresetID)
        }
    }

    private func loadFromDisk() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Keys.presets) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([TrailPreset].self, from: data) {
                presets = decoded
            }
        }
        if let idStr = d.string(forKey: Keys.activePresetID) {
            activePresetID = UUID(uuidString: idStr)
        }
    }
}
