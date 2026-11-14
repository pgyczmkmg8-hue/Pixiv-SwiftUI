import Foundation

@MainActor
final class PopularIllustSearcher {
    struct Batch {
        let items: [Illusts]
        let hasMore: Bool
    }

    struct Configuration: Equatable {
        let word: String
        let searchTarget: SearchTargetOption
        let showsAIGenerated: Bool
        let minimumBookmarkCount: Int
        let startDate: Date?
        let endDate: Date?
    }

    private static let tiers = [50000, 30000, 20000, 10000, 7500, 5000, 1000, 500, 250, 100]
    private static let pageSize = 30
    private static let pagesPerStep = 3
    private static let maxPagesPerTier = 17

    private let config: Configuration
    private let tiersToWalk: [Int]
    private var tierIndex = 0
    private var offset = 0
    private var pagesFetchedInTier = 0
    private var seenIDs = Set<Int>()
    private(set) var isExhausted = false

    init(config: Configuration) {
        self.config = config
        if config.searchTarget == .titleAndCaption {
            tiersToWalk = [0]
        } else {
            let floor = max(config.minimumBookmarkCount, Self.tiers.last ?? 100)
            let filtered = Self.tiers.filter { $0 >= floor }
            tiersToWalk = filtered.isEmpty ? [floor] : filtered
        }
    }

    func nextBatch(minimumItems: Int) async throws -> Batch {
        var collected: [Illusts] = []
        while collected.count < minimumItems, !isExhausted {
            let step = try await fetchStep()
            collected.append(contentsOf: step)
        }
        return Batch(items: collected, hasMore: !isExhausted)
    }

    private func fetchStep() async throws -> [Illusts] {
        let tier = tiersToWalk[tierIndex]
        let word = tier > 0 ? "\(config.word) \(tier)users入り" : config.word
        let startOffset = offset
        let pageCount = Self.pagesPerStep

        var pages: [[Illusts]] = []
        for index in 0..<pageCount {
            let response = try await PixivAPI.shared.searchAPI.searchIllustsPage(
                word: word,
                searchTarget: config.searchTarget.rawValue,
                sort: SearchSortOption.dateDesc.rawValue,
                searchAIType: config.showsAIGenerated ? 0 : 1,
                startDate: config.startDate,
                endDate: config.endDate,
                offset: startOffset + index * Self.pageSize,
                limit: Self.pageSize
            )
            pages.append(response.illusts)
            if response.illusts.count < Self.pageSize { break }
        }

        let allItems = pages.flatMap { $0 }
        let reachedEnd = pages.contains { $0.count < Self.pageSize } || allItems.isEmpty
        offset = startOffset + pageCount * Self.pageSize
        pagesFetchedInTier += pages.count

        if reachedEnd || pagesFetchedInTier >= Self.maxPagesPerTier {
            tierIndex += 1
            offset = 0
            pagesFetchedInTier = 0
            if tierIndex >= tiersToWalk.count { isExhausted = true }
        }

        let fresh = allItems.filter { item in
            (tier == 0 || item.totalBookmarks >= tier) && seenIDs.insert(item.id).inserted
        }
        return fresh.sorted { $0.totalBookmarks > $1.totalBookmarks }
    }
}
