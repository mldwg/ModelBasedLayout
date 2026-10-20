//
//  LayoutControllerTests.swift
//  ModelBasedLayoutTests
//
//  Created by Matteo Ludwig on 21.10.26.
//

import XCTest
@testable import ModelBasedLayout


final class LayoutControllerTests: XCTestCase {

    /// A list with rows of `rowHeight`. Every section is followed by a gap of `sectionGap`, so where an item ends up depends on the item counts of the sections before it.
    struct SectionedListModel: LayoutModel {
        static let rowHeight: CGFloat = 100
        static let sectionGap: CGFloat = 1000

        let dataSourceCounts: DataSourceCounts
        let width: CGFloat

        private func sectionStart(_ section: Int) -> CGFloat {
            dataSourceCounts.sections[..<section].reduce(0) { $0 + CGFloat($1.itemCount) * Self.rowHeight + Self.sectionGap }
        }

        var contentSize: CGSize {
            CGSize(width: width, height: sectionStart(dataSourceCounts.numberOfSections))
        }

        func elements(in rect: CGRect) -> [Element] {
            dataSourceCounts.indexPairs(for: 0..<dataSourceCounts.itemCount)
                .map { Element.cell($0) }
                .filter { layoutAttributes(for: $0)!.frame.intersects(rect) }
        }

        func layoutAttributes(for element: Element) -> LayoutAttributes? {
            guard element.elementKind == .cell, dataSourceCounts.contains(indexPair: element.indexPair) else { return nil }

            var attributes = LayoutAttributes(element: element)
            attributes.frame = CGRect(x: 0, y: sectionStart(element.indexPair.section) + CGFloat(element.indexPair.item) * Self.rowHeight,
                                      width: width, height: Self.rowHeight)
            return attributes
        }
    }

    /// Filtering out items in front of the visible ones must keep the item at the screen centre in place.
    func testTargetContentOffsetKeepsCenterItemWhenFiltering() {
        let viewSize = CGSize(width: 300, height: 500)
        var dataSourceCounts = DataSourceCounts(sections: [40, 60])

        // Item (1, 5) spans 5500..<5600, so its centre is at the centre of the screen.
        let bounds = CGRect(x: 0, y: 5300, width: viewSize.width, height: viewSize.height)

        let controller = LayoutController<SectionedListModel>(
            { dataSourceCounts, geometryInfo in SectionedListModel(dataSourceCounts: dataSourceCounts, width: geometryInfo.viewSize.width) },
            dataSourceCounts: { dataSourceCounts },
            geometryInfo: { GeometryInfo(viewSize: viewSize, safeAreaInsets: .zero) },
            boundsInfoProvider: { BoundsInfo(bounds: bounds, safeAreaInsets: .zero, adjustedContentInset: .zero) })
        controller.prepareIfNeeded()
        XCTAssertEqual(controller.layoutAttributes(for: .cell(IndexPair(item: 5, section: 1)))?.frame.midY, 5550)

        // Remove all items of the first section.
        dataSourceCounts = DataSourceCounts(sections: [0, 60])
        let context = InvalidationContext()
        context.invalidateModel = true
        controller.invalidateLayout(with: context)
        controller.prepareIfNeeded()
        controller.prepare(forDataUpdates: (0..<40).map { .deleteItem(indexPair: IndexPair(item: $0, section: 0)) })

        // Item (1, 5) now spans 1500..<1600 and should stay at the centre of the screen.
        let targetContentOffset = controller.targetContentOffset(forProposedContentOffset: bounds.origin)
        XCTAssertEqual(targetContentOffset, CGPoint(x: 0, y: 1300))

        controller.finalize()
    }
}
