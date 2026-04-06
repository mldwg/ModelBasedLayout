//
//  LayoutController.swift
//  
//
//  Created by Matteo Ludwig on 26.08.23.
//

import Foundation


class LayoutController<ModelType: LayoutModel> {
    
    private let stateController: LayoutStateController<ModelType>
    
    private var dataChange: DataBatchUpdate? = nil
    
    private var targetContentOffset: CGPoint? = nil
    private var targetContentOffsetAdjustment: CGPoint = .zero
    private var contentOffsetAnchor: ContentOffsetAnchor? = nil

    private(set) var boundsInfoProvider: () -> BoundsInfo

    /// The layout was invalidated and the controller has not run prepare yet.
    private var needsPrepare: Bool = false
    private var lastInvalidatedBounds: CGRect? = nil


    //private let transactionTracker = TransactionTracker()
    
    init(_ model: @escaping (_ dataSourceCounts: DataSourceCounts, _ geometryInfo: GeometryInfo) -> ModelType,
         dataSourceCounts: @escaping () -> DataSourceCounts,
         geometryInfo: @escaping () -> GeometryInfo,
         boundsInfoProvider: @escaping () -> BoundsInfo) {
        
        self.stateController = .init(modelProvider: model, dataSourceCountsProvider: dataSourceCounts, geometryInfoProvider: geometryInfo, boundsInfoProvider: boundsInfoProvider)
        
        self.boundsInfoProvider = boundsInfoProvider
    }
    
    // MARK: Accessors
    internal func layoutModel(_ state: LayoutState) -> ModelType? {
        self.stateController.layout(state)?.model
    }
    
    private func dataSourceCounts(_ state: LayoutState) -> DataSourceCounts? {
        self.stateController.layout(state)?.dataSourceCounts
    }
    
    private func geometryInfo(_ state: LayoutState) -> GeometryInfo? {
        self.stateController.layout(state)?.geometryInfo
    }
    
    private func stickyController(_ state: LayoutState) -> StickyController? {
        self.stateController.layout(state)?.stickyController
    }
    
    private func boundsController(_ state: LayoutState) -> BoundsController? {
        self.stateController.layout(state)?.boundsController
    }
    
    // MARK: Content Size
    var collectionViewContentSize: CGSize {
        if let model = self.layoutModel(.afterUpdate) {
            return model.contentSize
        }
        return .zero
    }
    
    // MARK: Prepare & Finalize
    func prepareIfNeeded() {
        guard self.needsPrepare else { return }
        
        if self.layoutModel(.afterUpdate) == nil {
            self.stateController.pushNewLayout()
        }
        
        self.stateController.prepare()
        
        self.boundsController(.afterUpdate)?.updateBoundsIfNeeded()
        
        self.targetContentOffsetAdjustment = .zero
        
        self.layoutModel(.afterUpdate)?.prepare()
        self.layoutModel(.beforeUpdate)?.prepare()
        

        self.needsPrepare = false
    }
    
    func prepareForBoundsChange(oldBounds: CGRect) {
        prepareIfNeeded()
        prepareContentOffsetAnchor(oldBounds: oldBounds)
        if self.dataSourceCounts(.beforeUpdate) == nil && self.geometryInfo(.afterUpdate) != stateController.geometryInfoProvider() {
            self.stateController.pushNewLayout()
        }
        self.boundsController(.beforeUpdate)?.freeze()
        self.stickyController(.beforeUpdate)?.willBeReplaced()
    }
    
    func prepare(forCollectionViewUpdates updateItems: [NativeCollectionViewUpdateItem]) {
        self.prepareIfNeeded()
        
        guard !updateItems.isEmpty else { return }
        
        // Sometimes, we get updateItems without being invalidated first. AFAIK this only occurs if the updateItems only include reloads. To fix this, we ensure that we have a record of the previous datasource counts
        if self.dataSourceCounts(.beforeUpdate) == nil {
            self.stateController.pushNewLayout()
        }
        
        // Create DataBatchUpdate to be able to match new and old index pairs and to determine which items are reloaded, moved, inserted or deleted. 
        if let dataSourceCountsBeforeUpdate = self.dataSourceCounts(.beforeUpdate) {
            self.dataChange = DataBatchUpdate(dataSourceCounts: dataSourceCountsBeforeUpdate, updateItems: updateItems)
        }
        
        self.prepareTargetContentOffset()
        
        if let targetContentOffset = self.targetContentOffset {
            self.boundsController(.afterUpdate)?.updateContentOffset(targetContentOffset)
        }
    }
    
    func finalize() {
        self.stateController.clearLayoutBefore()
        self.dataChange = nil
        self.targetContentOffsetAdjustment = .zero
        self.targetContentOffset = nil
        self.contentOffsetAnchor = nil
    }
    
    private func usesStickyViews() -> Bool {
        self.stickyController(.afterUpdate)?.usesStickyViews ?? false
    }
    
    private func prepareContentOffsetAnchor(oldBounds: CGRect) -> ContentOffsetAnchor? {
        if contentOffsetAnchor == nil, var currentBounds = self.boundsController(.afterUpdate)?.boundsInfo {
            if currentBounds.bounds.size == oldBounds.size {
                currentBounds.bounds = oldBounds
            }
            contentOffsetAnchor = stateController.layout(.afterUpdate)?.model.contentOffsetAnchor(in: currentBounds)
        }
        return contentOffsetAnchor
    }
    
    // MARK: Content Offset Adjustment
    private func prepareTargetContentOffset() {
        guard let before = self.stateController.layout(.beforeUpdate),
              let after = self.stateController.layout(.afterUpdate),
              let result = self.targetContentOffset(from: before, to: after, newBounds: nil) else {
            return
            
        }
        
        self.targetContentOffset = result
    }
    
    func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        if targetContentOffset == nil {
            self.prepareTargetContentOffset()
        }
        
        guard let targetContentOffset = self.targetContentOffset else {
            return proposedContentOffset
        }
        
        self.targetContentOffsetAdjustment = proposedContentOffset - targetContentOffset
        return targetContentOffset
    }
    
    private func targetContentOffset(from originContainer: LayoutContainer<ModelType>, to targetContainer: LayoutContainer<ModelType>, newBounds: CGRect?) -> CGPoint? {
        let oldBounds = originContainer.boundsController.boundsInfo
        var newBoundsInfo = self.boundsInfoProvider()
        if let newBounds {
            newBoundsInfo.bounds = newBounds
        }
        guard oldBounds.bounds.size > .zero && newBoundsInfo.bounds.size > .zero else {
            return nil
        }
        
        guard var contentOffsetAnchor = prepareContentOffsetAnchor(oldBounds: oldBounds.bounds) else {
            return nil
        }
        

        if let dataChange = dataChange {
            if let updatedIndexPair = dataChange.indexPairAfterUpdate(for: contentOffsetAnchor.element.indexPair) {
                contentOffsetAnchor.element.indexPair = updatedIndexPair
            } else {
                return nil
            }
        }
        
        let newContentOffset = targetContainer.model.contentOffset(for: contentOffsetAnchor, proposedBounds: newBoundsInfo, currentBounds: oldBounds)
        

        let contentSize = targetContainer.model.contentSize
        let targetInsets = newBoundsInfo.adjustedContentInset

        let minContentOffset = CGPoint(x: -targetInsets.left,
                                       y: -targetInsets.top)
        let maxContentOffset = CGPoint(x: contentSize.width + targetInsets.right - newBoundsInfo.bounds.width,
                                       y: contentSize.height + targetInsets.bottom - newBoundsInfo.bounds.height)
        
        let result = CGPoint(x: max(minContentOffset.x, min(maxContentOffset.x, newContentOffset.x)),
                             y: max(minContentOffset.y, min(maxContentOffset.y, newContentOffset.y)))
        
        log("controller", "targetContentOffset", "anchor: \(contentOffsetAnchor.element), result: \(result)")
        return result
    }
    
    private func contentOffsetAdjustmentFalback(from originContainer: LayoutContainer<ModelType>, to targetContainer: LayoutContainer<ModelType>) -> CGSize {
        let contentSizeBefore = originContainer.model.contentSize
        let contentSizeAfter = targetContainer.model.contentSize
        
        guard contentSizeBefore > .zero else { return .zero }
        
        let boundsInfoBefore = originContainer.boundsController.boundsInfo
        let boundsInfoAfter = targetContainer.boundsController.boundsInfo
        
        let currentContentOffset = boundsInfoAfter.bounds.origin.cgSize
        
        let halfBoundsSizeBefore = (originContainer.geometryInfo.viewSize/2)
        let halfBoundsSizeAfter = (targetContainer.geometryInfo.viewSize/2)
        
        let insetBefore = CGSize(width: boundsInfoBefore.adjustedContentInset.left, height: boundsInfoBefore.adjustedContentInset.top)
        let insetAfter = CGSize(width: boundsInfoAfter.adjustedContentInset.left, height: boundsInfoAfter.adjustedContentInset.top)
        let insetDiff = insetBefore - insetAfter
        
        let scrollRatio = (currentContentOffset + halfBoundsSizeBefore - insetDiff) / contentSizeBefore
        
        return (scrollRatio * contentSizeAfter - halfBoundsSizeAfter) - currentContentOffset
    }
    
    func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        var proposal = self.boundsInfoProvider()
        proposal.bounds.origin = proposedContentOffset
        
        return self.layoutModel(.afterUpdate)?.contentOffset(proposedBounds: proposal, scrollingVelocity: velocity) ?? proposedContentOffset
    }
   
    // MARK: Invalidation
    func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard self.lastInvalidatedBounds != newBounds else {
            return false
        }
        self.lastInvalidatedBounds = newBounds
        
        self.boundsController(.afterUpdate)?.updateBounds(newBounds)
        
        if newBounds.size != self.geometryInfo(.afterUpdate)?.viewSize {
            return true
        }
        
        // When a bounds change animation involves a size change (rotation), true must be returned
        // once so UIKit discards its per-cell attribute cache and re-queries the visible rect.
        // Without this, cells whose attributes were already cached from a previous portrait query would never
        // be refreshed to their correct landscape positions when the new viewport falls inside that cached range.
        if let viewSizeBeforeUpdate =  self.geometryInfo(.beforeUpdate)?.viewSize,
           newBounds.size != viewSizeBeforeUpdate {
            return true
        }

        if self.stickyController(.afterUpdate)?.shouldInvalidateLayout(forBoundsChange: newBounds) == true {
            return true
        }
        
        if var newBoundsInfo = self.boundsController(.afterUpdate)?.boundsInfo {
            newBoundsInfo.bounds = newBounds
            
            if self.layoutModel(.afterUpdate)?.elements(affectedByBoundsChange: newBoundsInfo, in: newBounds).isEmpty == false {
                return true
            }
        }
        
        return false
    }
    
    func configureInvalidationContext(context: InvalidationContext, forBoundsChange newBounds: CGRect) {
        guard let geometryBefore = self.geometryInfo(.afterUpdate), geometryBefore.viewSize != .zero else {
            
            // If we are in the initial layout pass after the collectionView was instanciated, we may have a cached viewSize of zero.
            // In such a case, performing any actual invalidation (e.g. contentOffsetAdjusten) would be pointless and can cause crashes.
            // Therefore, simply replace the model and move on.
            // Note: This case should no longer happen due to models only being created when the viewSize is not zero, but this check is kept here just for additional safety.
            context.invalidateModel = true
            return
        }

        if newBounds.size != geometryBefore.viewSize,
           let afterLayout = self.stateController.layout(.afterUpdate),
           !context.invalidateGeometryInfo {
            // If the viewSize changed, setup the contentSizeAdjustment and contentOffsetAdjustment of the InvalidationContext.
            
            context.invalidateGeometryInfo = true
            
            if let newLayout = self.stateController.makeNewLayout(forNewBounds: newBounds) {
                context.contentSizeAdjustment = newLayout.model.contentSize - afterLayout.model.contentSize
                
                let currentBounds = boundsInfoProvider().bounds
                
                if let target = self.targetContentOffset(from: afterLayout, to: newLayout, newBounds: newBounds) {
                    log("controller", "configureInvalidationContext", "targetContentOffset: \(target)")
                    context.contentOffsetAdjustment = (target - currentBounds.origin)
                } else {
                    context.contentOffsetAdjustment = self.contentOffsetAdjustmentFalback(from: afterLayout, to: newLayout).cgPoint
                }
            }
        }
        
        if !context.invalidateGeometryInfo {
            // Explicitly invalidating elements when the view geometry changes causes intense glitches on iPad in combination with a SplitViewController set to tiling mode
            // Therefore, only invalidate explicitly if the geometry was not invalidated
            
            var newBoundsInfo = self.boundsInfoProvider()
            newBoundsInfo.bounds = newBounds
            
            let dynamicElementsToInvalidate = self.layoutModel(.afterUpdate)?.elements(affectedByBoundsChange: newBoundsInfo, in: newBounds)
            for element in (dynamicElementsToInvalidate ?? []) {
                context.invalidateElement(element, dynamic: true)
            }
            
            if self.usesStickyViews(), let stickyController = self.stickyController(.afterUpdate) {
                stickyController.configureInvalidationContext(forBoundsChange: newBounds, with: context)
            }
        }
    }
    
    func invalidateLayout(with context: InvalidationContext) {
        self.needsPrepare = true
        
        self.stickyController(.afterUpdate)?.invalidate(with: context)
        
        if context.invalidateDataSourceCounts || context.invalidateEverything || context.invalidateModel || context.invalidateGeometryInfo  {
            self.stateController.pushNewLayout()
            self.boundsController(.beforeUpdate)?.freeze()
            self.stickyController(.beforeUpdate)?.willBeReplaced()
        }
        
        self.boundsController(.afterUpdate)?.invalidate()
    }
    
    // MARK: Self Sizing
    func shouldInvalidateLayout(forSelfSizingElement element: Element, preferredSize: CGSize) -> Bool {
        guard let attrsBefore = self.layoutAttributes(for: element) else { return false }
        self.layoutModel(.afterUpdate)?.adjustForSelfSizing(element: element, preferredSize: preferredSize)
        let attrsAfter = self.layoutAttributes(for: element)
        
        return attrsBefore.frame.size != attrsAfter?.frame.size
    }
    
    func configureInvalidationContext(context: InvalidationContext, forSelfSizingElement element: Element, preferredSize: CGSize) {
        context.invalidateElement(element)
        context.invalidateStickyCache = true
    }
    
    // MARK: Animations
    func transitionAnimation(for element: Element, transition: ElementTransition, state: LayoutState) -> ElementTransitionAnimation {
        self.layoutModel(state)?.transitionAnimation(for: element, transition: transition) ?? .none
    }
    
    // MARK: Rect
    func layoutAttributesForElements(in rect: CGRect) -> [LayoutAttributes]? {
        let items = self.layoutModel(.afterUpdate)?.elements(in: rect)
        return items?.compactMap { (element: Element) -> LayoutAttributes? in
            self.layoutAttributes(for: element)
        }.filter {
            $0.frame.intersects(rect)
        }
        
    }
    
    
    // MARK: Layout Attributes
    func layoutAttributes(for element: Element) -> LayoutAttributes? {
        switch element.elementKind {
        case .cell:
            return self.layoutAttributes(forCellAt: element.indexPair)
        case .header, .footer, .additionalSupplementaryView:
            return self.layoutAttributes(forSupplementaryElement: element)
        case .decorativeView:
            return nil
        }
    }
    
    // MARK: Cells
    
    /// Returns the layout attributes for the cell that is about to appear at the specified index pair.
    /// - Parameter indexPair: The index pair of the cell.
    /// - Returns: The layout attributes for the cell that is about to appear at the specified index pair.
    func layoutAttributes(forAppearingItemAt indexPair: IndexPair) -> LayoutAttributes? {
        
        // If we have a data change, we need to check if the indexPair is affected by it.
        if let dataChange = self.dataChange {
            let reload = dataChange.willReload(indexPair, state: .afterUpdate)
            
            if let indexPairBeforeUpdate = dataChange.indexPairBeforeUpdate(for: indexPair), !reload {
                // If the item is not new, we return the layout attributes from the beforeUpdate layout. We know that the item is not new because it has a corresponding indexPair in the beforeUpdate layout and was not marked for reload.
                // We also need to adjust the indexPair of the beforeLayout layout attributes to the new indexPair.
                return self.layoutModel(.beforeUpdate)?.layoutAttributes(for: .cell(indexPairBeforeUpdate))?.withIndexPair(indexPair)
            } else if self.dataSourceCounts(.afterUpdate)?.contains(indexPair: indexPair) == true {
                // If the item does not have a corresponding indexPair in the beforeUpdate layout or is marked for reload, we treat it as a new item.
                let transition: ElementTransition = reload ? .reload : .insertion
                
                // Depending on the transition animation, we return the layout attributes from the afterUpdate layout with the appropriate adjustments.
                switch self.transitionAnimation(for: .cell(indexPair), transition: transition, state: .afterUpdate) {
                case .none:
                    return self.layoutModel(.afterUpdate)?.layoutAttributes(for: .cell(indexPair))?.offset(by: self.targetContentOffsetAdjustment)
                case .opacity:
                    return self.layoutModel(.afterUpdate)?.layoutAttributes(for: .cell(indexPair))?.with(alpha: 0).offset(by: self.targetContentOffsetAdjustment)
                case .custom:
                    return self.layoutModel(.afterUpdate)?.layoutAttributes(for: .cell(indexPair), frame: .initial(reload: reload))?.offset(by: self.targetContentOffsetAdjustment)
                }
            } else {
                return nil
            }
        }
        
        guard self.dataSourceCounts(.beforeUpdate)?.contains(indexPair: indexPair) == true else { 
            // If the item is not in the beforeUpdate layout, we cannot return an appearing layout attribute (since it is not contained in the beforeUpdate layout), so we return nil.
            return nil 
        }

        // If we don't have a data change, we assume that the item is not new but simply scrolled into view due to a bounds change or similar.
        // In order to have the item animate properly, we need to return the layout attributes from the beforeUpdate layout.
        return self.layoutModel(.beforeUpdate)?.layoutAttributes(for: .cell(indexPair))
    }
    
    /// Returns the layout attributes for the cell at the specified index pair.
    /// - Parameter indexPair: The index pair of the cell.
    /// - Returns: The layout attributes for the cell at the specified index pair.
    func layoutAttributes(forCellAt indexPair: IndexPair) -> LayoutAttributes? {
        let layoutAttrs = self.layoutModel(.afterUpdate)?.layoutAttributes(for: .cell(indexPair))
        return layoutAttrs
    }
    
    func layoutAttributes(forDisappearingItemAt indexPair: IndexPair) -> LayoutAttributes? {
        if let dataChange = self.dataChange {
            let reload = dataChange.willReload(indexPair, state: .beforeUpdate)
            
            if let indexPairAfterUpdate = dataChange.indexPairAfterUpdate(for: indexPair), !reload {
                return self.layoutModel(.afterUpdate)?.layoutAttributes(for: .cell(indexPairAfterUpdate))?.withIndexPair(indexPair)
            } else if self.dataSourceCounts(.beforeUpdate)?.contains(indexPair: indexPair) == true {
                let transition: ElementTransition = reload ? .reload : .deletion
                
                switch self.transitionAnimation(for: .cell(indexPair), transition: transition, state: .beforeUpdate) {
                case .none:
                    return self.layoutModel(.beforeUpdate)?.layoutAttributes(for: .cell(indexPair))
                    
                case .opacity:
                    return self.layoutModel(.beforeUpdate)?.layoutAttributes(for: .cell(indexPair))?.with(alpha: 0)
                    
                case .custom:
                    return self.layoutModel(.beforeUpdate)?.layoutAttributes(for: .cell(indexPair), frame: .final(reload: reload))
                }
            } else {
                return nil
            }
        }
        
        let attrs = self.layoutModel(.afterUpdate)?.layoutAttributes(for: .cell(indexPair))
        return attrs
    }
    
    
    
    // MARK: Supplementary Views
    
    
    func layoutAttributes(forAppearingSupplementaryElement element: Element) -> LayoutAttributes? {
        assert(element.elementKind.isSupplementaryView)
        
        if let dataChange = self.dataChange {
            let reload = dataChange.willReload(element.indexPair, state: .afterUpdate)
            
            if let indexPairBeforeUpdate = dataChange.indexPairBeforeUpdate(for: element.indexPair), !reload {
                return self.stickyController(.beforeUpdate)?.layoutAttributes(for: Element(indexPair: indexPairBeforeUpdate, elementKind: element.elementKind))?.withIndexPair(element.indexPair)
                
            } else if self.dataSourceCounts(.afterUpdate)?.contains(indexPair: element.indexPair) == true  {
                let transition: ElementTransition = reload ? .reload : .insertion
                
                switch self.transitionAnimation(for: element, transition: transition, state: .afterUpdate) {
                    
                case .none:
                    return self.stickyController(.afterUpdate)?.layoutAttributes(for: element)?.offset(by: self.targetContentOffsetAdjustment)
                case .opacity:
                    return self.stickyController(.afterUpdate)?.layoutAttributes(for: element)?.with(alpha: 0).offset(by: self.targetContentOffsetAdjustment)
                    
                case .custom:
                    return self.layoutModel(.afterUpdate)?.layoutAttributes(for: element, frame: .initial(reload: reload)).flatMap {
                        self.stickyController(.afterUpdate)?.stickify($0)
                    }?.offset(by: self.targetContentOffsetAdjustment)
                }
            } else {
                return nil
            }
        }
        
        guard self.dataSourceCounts(.beforeUpdate)?.contains(indexPair: element.indexPair) == true else { return nil }
        return self.stickyController(.beforeUpdate)?.layoutAttributes(for: element)
    }
    
    func layoutAttributes(forSupplementaryElement element: Element) -> LayoutAttributes? {
        assert(element.elementKind.isSupplementaryView)
        
        return self.stickyController(.afterUpdate)?.layoutAttributes(for: element)
    }
    
    func layoutAttributes(forDisappearingSupplementaryElement element: Element) -> LayoutAttributes? {
        assert(element.elementKind.isSupplementaryView)
        
        if let dataChange = self.dataChange {
            let reload = dataChange.willReload(element.indexPair, state: .beforeUpdate)
            
            if let indexPairAfterUpdate = dataChange.indexPairAfterUpdate(for: element.indexPair), !reload {
                return self.stickyController(.afterUpdate)?.layoutAttributes(for: Element(indexPair: indexPairAfterUpdate,
                                                                                          elementKind: element.elementKind))?.withIndexPair(element.indexPair)
            } else if self.dataSourceCounts(.beforeUpdate)?.contains(indexPair: element.indexPair) == true {
                let transition: ElementTransition = reload ? .reload : .deletion
                
                switch self.transitionAnimation(for: element, transition: transition, state: .beforeUpdate)  {
                case .none:
                    var layoutAttrs = self.stickyController(.beforeUpdate)?.layoutAttributes(for: element)
                    
                    // For some reason, we need to change the zIndex of the layout attributes by any amount for it to be respected at all. It is not clear yet why.
                    layoutAttrs?.zIndex += 1
                    return layoutAttrs
                case .opacity:
                    var layoutAttrs = self.stickyController(.beforeUpdate)?.layoutAttributes(for: element)?.with(alpha: 0)
                    
                    // For some reason, we need to change the zIndex of the layout attributes by any amount for it to be respected at all. It is not clear yet why.
                    layoutAttrs?.zIndex += 1
                    return layoutAttrs
                    
                case .custom:
                    return self.layoutModel(.beforeUpdate)?.layoutAttributes(for: element, frame: .final(reload: reload)).flatMap {
                        var attrs = self.stickyController(.beforeUpdate)?.stickify($0)
                        attrs?.zIndex += 1
                        return attrs
                    }
                }
            } else {
                return nil
            }
        }
        
        return self.stickyController(.afterUpdate)?.layoutAttributes(for: element)
    }
}
