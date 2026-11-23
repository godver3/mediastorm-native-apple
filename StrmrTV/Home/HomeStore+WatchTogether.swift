import Foundation

extension HomeStore {
    /// Reloads the Watch Together row (Home polls it while on screen); a full load running
    /// fetches it anyway.
    func reloadWatchTogether() async {
        guard settings != nil, loadsRunning == 0 else { return }
        let rows = plan.filter { $0.source == .watchTogether }
        guard !rows.isEmpty else { return }
        await loadRows(rows, generation: loadGeneration)
    }
}
