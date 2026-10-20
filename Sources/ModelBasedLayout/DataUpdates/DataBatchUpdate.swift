//
//  DataBatchUpdate.swift
//  ModelBasedLayout
//
//  Created by Matteo Ludwig on 18.07.23.
//

import Foundation



struct DataBatchUpdate {

    /// The section index after the update for every section before the update, -1 for deleted sections.
    private var sectionIndiciesAfterUpdate = IndexShifts()

    /// The item indices of every section before the update, keyed by section index before the update. `nil` for sections whose items keep their indices.
    /// Items that moved to another section are -1 here and stored in `crossSectionMovesAfterUpdate`.
    private var itemIndiciesAfterUpdate: [IndexShifts?] = []

    /// The item indices of every section after the update, keyed by section index after the update. `nil` for sections whose items keep their indices.
    private var itemIndiciesBeforeUpdate: [IndexShifts?] = []

    private var crossSectionMovesAfterUpdate: [IndexPair: IndexPair] = [:]
    private var crossSectionMovesBeforeUpdate: [IndexPair: IndexPair] = [:]

    private var itemReloads: Set<IndexPair> = .init()
    private var sectionReloads: Set<Int> = .init()

    private var dataSourceCounts: DataSourceCounts

    init(dataSourceCounts: DataSourceCounts, updateItems: [DataUpdate]) {
        self.dataSourceCounts = dataSourceCounts

        addUpdateItems(updateItems)
    }

    init(dataSourceCounts: DataSourceCounts, updateItems: [NativeCollectionViewUpdateItem]) {
        self = .init(dataSourceCounts: dataSourceCounts, updateItems: updateItems.compactMap {DataUpdate($0)})
    }

    func indexPairAfterUpdate(for indexPair: IndexPair) -> IndexPair? {
        guard let sectionIndexAfterUpdate = sectionIndiciesAfterUpdate.indexAfterUpdate(for: indexPair.section) else { return nil }

        if !crossSectionMovesAfterUpdate.isEmpty, let indexPairAfterUpdate = crossSectionMovesAfterUpdate[indexPair] {
            return indexPairAfterUpdate
        }

        guard dataSourceCounts.contains(indexPair: indexPair) else { return nil }

        guard let itemIndicies = itemIndiciesAfterUpdate[indexPair.section] else {
            return IndexPair(item: indexPair.item, section: sectionIndexAfterUpdate)
        }
        return itemIndicies.indexAfterUpdate(for: indexPair.item).map { IndexPair(item: $0, section: sectionIndexAfterUpdate) }
    }

    func indexPairBeforeUpdate(for indexPair: IndexPair) -> IndexPair? {
        if !crossSectionMovesBeforeUpdate.isEmpty, let indexPairBeforeUpdate = crossSectionMovesBeforeUpdate[indexPair] {
            return indexPairBeforeUpdate
        }

        guard let sectionIndexBeforeUpdate = sectionIndiciesAfterUpdate.indexBeforeUpdate(for: indexPair.section) else { return nil }

        guard let itemIndicies = itemIndiciesBeforeUpdate[indexPair.section] else {
            let indexPairBeforeUpdate = IndexPair(item: indexPair.item, section: sectionIndexBeforeUpdate)
            return dataSourceCounts.contains(indexPair: indexPairBeforeUpdate) ? indexPairBeforeUpdate : nil
        }
        return itemIndicies.indexBeforeUpdate(for: indexPair.item).map { IndexPair(item: $0, section: sectionIndexBeforeUpdate) }
    }

    func willReload(_ indexPair: IndexPair, state: LayoutState) -> Bool {
        var indexPair = indexPair
        if state == .beforeUpdate {
            guard let indexPairBefore = self.indexPairBeforeUpdate(for: indexPair) else { return false }
            indexPair = indexPairBefore
        }
        return self.sectionReloads.contains(indexPair.section) || self.itemReloads.contains(indexPair)
    }

    private mutating func addUpdateItems(_ dataUpdates: [DataUpdate]) {

        var sectionSummary: IndexBasedSummary = .init(initialItemCount: dataSourceCounts.numberOfSections)
        var itemInserts: [IndexPair] = []
        var itemDeletions: [IndexPair] = []
        var itemMoves: [(IndexPair, IndexPair)] = []

        for dataUpdate in dataUpdates {
            switch dataUpdate {
            case .deleteSection(let sectionIndex):
                sectionSummary.deletions.append(sectionIndex)

            case .insertSection(let sectionIndex):
                sectionSummary.insertions.append(sectionIndex)

            case .moveSection(let sectionIndexBeforeUpdate, let sectionIndexAfterUpdate):
                sectionSummary.moves.append((sectionIndexBeforeUpdate, sectionIndexAfterUpdate))

            case .reloadSection(let sectionIndexBeforeUpdate, _):
                sectionReloads.insert(sectionIndexBeforeUpdate)

            case .deleteItem(let indexPair):
                itemDeletions.append(indexPair)

            case .insertItem(let indexPair):
                itemInserts.append(indexPair)

            case .moveItem(let indexPairBeforeUpdate, let indexPairAfterUpdate):
                itemMoves.append((indexPairBeforeUpdate, indexPairAfterUpdate))

            case .reloadItem(let indexPairBeforeUpdate, _):
                itemReloads.insert(indexPairBeforeUpdate)
            }
        }

        sectionIndiciesAfterUpdate = IndexShifts(summary: sectionSummary)
        let moves = IndexShifts(summary: IndexBasedSummary(initialItemCount: dataSourceCounts.numberOfSections + sectionSummary.insertions.count,
                                                          moves: sectionSummary.moves))

        let numberOfSectionsAfterUpdate = sectionIndiciesAfterUpdate.countAfterUpdate
        var perSectionSummaries: [IndexBasedSummary] = Array(repeating: .init(), count: numberOfSectionsAfterUpdate)

        for indexPair in itemDeletions {
            guard let sectionIndexAfterUpdate = sectionIndiciesAfterUpdate.indexAfterUpdate(for: indexPair.section) else { continue }
            perSectionSummaries[sectionIndexAfterUpdate].deletions.append(indexPair.item)
        }

        for indexPair in itemInserts {
            guard let sectionIndexAfterUpdate = moves.indexAfterUpdate(for: indexPair.section),
                  perSectionSummaries.indices.contains(sectionIndexAfterUpdate) else { continue }
            perSectionSummaries[sectionIndexAfterUpdate].insertions.append(indexPair.item)
        }

        for (indexPairBeforeUpdate, indexPairAfterUpdate) in itemMoves {
            guard perSectionSummaries.indices.contains(indexPairAfterUpdate.section) else { continue }

            // Summaries are indexed by section index after the update, but the source of a move is given in indices before the update.
            let sourceSectionIndexAfterUpdate = sectionIndiciesAfterUpdate.indexAfterUpdate(for: indexPairBeforeUpdate.section)

            if sourceSectionIndexAfterUpdate == indexPairAfterUpdate.section {
                perSectionSummaries[indexPairAfterUpdate.section].moves.append((indexPairBeforeUpdate.item, indexPairAfterUpdate.item))
            } else {
                if let sourceSectionIndexAfterUpdate {
                    perSectionSummaries[sourceSectionIndexAfterUpdate].deletions.append(indexPairBeforeUpdate.item)
                }
                perSectionSummaries[indexPairAfterUpdate.section].insertions.append(indexPairAfterUpdate.item)

                crossSectionMovesAfterUpdate[indexPairBeforeUpdate] = indexPairAfterUpdate
                crossSectionMovesBeforeUpdate[indexPairAfterUpdate] = indexPairBeforeUpdate
            }
        }

        itemIndiciesAfterUpdate = Array(repeating: nil, count: dataSourceCounts.numberOfSections)
        itemIndiciesBeforeUpdate = Array(repeating: nil, count: numberOfSectionsAfterUpdate)

        for (sectionIndexBeforeUpdate, section) in dataSourceCounts.sections.enumerated() {

            guard let sectionIndexAfterUpdate = sectionIndiciesAfterUpdate.indexAfterUpdate(for: sectionIndexBeforeUpdate) else {
                // No need to explcitlty delete items of a section if the entire section is deleted
                continue
            }

            var summary = perSectionSummaries[sectionIndexAfterUpdate]
            // Sections without changes keep their item indices, so there is nothing to store.
            guard !summary.isEmpty else { continue }
            summary.initialItemCount = section.itemCount

            let itemIndicies = IndexShifts(summary: summary)
            itemIndiciesAfterUpdate[sectionIndexBeforeUpdate] = itemIndicies
            itemIndiciesBeforeUpdate[sectionIndexAfterUpdate] = itemIndicies
        }
    }
}

struct IndexBasedSummary {
    var initialItemCount: Int
    var deletions: [Int]
    var insertions: [Int]
    var moves: [(Int, Int)]

    var isEmpty: Bool {
        deletions.isEmpty && insertions.isEmpty && moves.isEmpty
    }

    init(initialItemCount: Int = 0, deletions: [Int] = [], insertions: [Int] = [], moves: [(Int, Int)] = []) {
        self.initialItemCount = initialItemCount
        self.deletions = deletions
        self.insertions = insertions
        self.moves = moves
    }
}


/// Maps the indices of one level (sections, or the items of one section) between before and after an update, in both directions.
struct IndexShifts {
    /// The index after the update for every index before the update, -1 for removed indices.
    private var indiciesAfterUpdate: ContiguousArray<Int> = []
    /// The index before the update for every index after the update, -1 for inserted indices.
    private var indiciesBeforeUpdate: ContiguousArray<Int> = []

    var countAfterUpdate: Int {
        indiciesBeforeUpdate.count
    }

    init() {}

    /// Deletions and the sources of moves are indices before the update, insertions and the destinations of moves are indices after the update, the same way UIKit reports them.
    /// - Complexity: O(n + k), where n is the number of indices before the update and k the number of changes.
    init(summary: IndexBasedSummary) {
        let count = summary.initialItemCount

        // -2: not placed yet, -1: deleted or moved
        var indiciesAfterUpdate = ContiguousArray(repeating: -2, count: count)
        var removedCount = 0

        for deletion in summary.deletions where deletion >= 0 && deletion < count && indiciesAfterUpdate[deletion] == -2 {
            indiciesAfterUpdate[deletion] = -1
            removedCount += 1
        }
        for (source, _) in summary.moves where source >= 0 && source < count && indiciesAfterUpdate[source] == -2 {
            indiciesAfterUpdate[source] = -1
            removedCount += 1
        }

        // Slots after the update that are taken by insertions (-2) or moves (index before the update). Free slots are -1.
        var fixedSlots = ContiguousArray(repeating: -1, count: count - removedCount + summary.insertions.count + summary.moves.count)
        var fixedSlotCount = 0

        for insertion in summary.insertions where insertion >= 0 && insertion < fixedSlots.count {
            if fixedSlots[insertion] == -1 {
                fixedSlotCount += 1
            }
            fixedSlots[insertion] = -2
        }
        for (source, destination) in summary.moves where source >= 0 && source < count && destination >= 0 && destination < fixedSlots.count {
            if fixedSlots[destination] == -1 {
                fixedSlotCount += 1
            }
            fixedSlots[destination] = source
        }

        // Fill the free slots with the remaining indices, in order.
        let countAfterUpdate = count - removedCount + fixedSlotCount
        var indiciesBeforeUpdate = ContiguousArray(repeating: -1, count: countAfterUpdate)
        var next = 0

        for slot in 0..<countAfterUpdate {
            let fixedSlot = fixedSlots[slot]
            if fixedSlot >= 0 {
                indiciesBeforeUpdate[slot] = fixedSlot
                indiciesAfterUpdate[fixedSlot] = slot
            } else if fixedSlot == -1 {
                while next < count && indiciesAfterUpdate[next] != -2 {
                    next += 1
                }
                guard next < count else { continue }
                indiciesBeforeUpdate[slot] = next
                indiciesAfterUpdate[next] = slot
                next += 1
            }
        }

        // Only left over if the summary was inconsistent.
        for index in next..<count where indiciesAfterUpdate[index] == -2 {
            indiciesAfterUpdate[index] = -1
        }

        self.indiciesAfterUpdate = indiciesAfterUpdate
        self.indiciesBeforeUpdate = indiciesBeforeUpdate
    }

    func indexAfterUpdate(for index: Int) -> Int? {
        guard indiciesAfterUpdate.indices.contains(index) else { return nil }
        let result = indiciesAfterUpdate[index]
        return result >= 0 ? result : nil
    }

    func indexBeforeUpdate(for index: Int) -> Int? {
        guard indiciesBeforeUpdate.indices.contains(index) else { return nil }
        let result = indiciesBeforeUpdate[index]
        return result >= 0 ? result : nil
    }
}
