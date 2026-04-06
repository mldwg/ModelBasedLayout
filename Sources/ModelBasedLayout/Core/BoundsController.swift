//
//  BoundsController.swift
//  
//
//  Created by Matteo Ludwig on 13.09.23.
//

import Foundation


class BoundsController {
    
    private var boundsInfoProvider: () -> BoundsInfo
    
    private var _boundsInfo: BoundsInfo = .init(bounds: .zero, safeAreaInsets: .zero, adjustedContentInset: .zero)
    
    private var viewSize: CGSize
    
    enum State {
        case initializing, valid, invalid, frozen
    }
    private var state: State = .initializing
    
    
    var boundsInfo: BoundsInfo {
        self.updateBoundsIfNeeded()
        return self._boundsInfo
    }
    
    var bounds: CGRect {
        return self.boundsInfo.bounds
    }
    
    var safeAreaBounds: CGRect {
        return self.boundsInfo.safeAreaBounds
    }
    
    init(boundsInfoProvider: @escaping () -> BoundsInfo, viewSize: CGSize) {
        self.boundsInfoProvider = boundsInfoProvider
        self.viewSize = viewSize
        self.updateBoundsIfNeeded()
    }
    
    func invalidate() {
        guard self.state == .valid else { return }
        self.state = .invalid
    }
    
    func freeze() {
        if state == .initializing {
            self._boundsInfo = self.boundsInfoProvider()
        }
        self.state = .frozen
    }
    
    func updateBoundsIfNeeded() {
        guard self.state == .invalid || self.state == .initializing else { return }
        
        let newBoundsInfo = self.boundsInfoProvider()

        guard self.updateBounds(newBoundsInfo.bounds) else { return }

        self._boundsInfo = newBoundsInfo
        self.state = .valid
    }
    
    func updateContentOffset(_ contentOffset: CGPoint) {
        self.updateBoundsIfNeeded()
        
        guard self.state != .frozen else { return }
        
        self._boundsInfo.bounds = CGRect(origin: contentOffset, size: self._boundsInfo.bounds.size)
        self.state = .valid
    }
    
    @discardableResult
    func updateBounds(_ newBounds: CGRect) -> Bool {
        guard newBounds.size == self.viewSize else {
            if self.state != .initializing {
                self.freeze()
            }
            return false
        }
        
        self._boundsInfo.bounds = newBounds
        return true
    }
    
}
