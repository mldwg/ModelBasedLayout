//
//  ChunkedRectMapTests.swift
//  ModelBasedLayoutTests
//
//  Created by Matteo Ludwig on 21.10.26.
//

import XCTest
@testable import ModelBasedLayout


final class ChunkedRectMapTests: XCTestCase {

    func testZeroSizeRectOnChunkBoundary() {
        let map = ChunkedRectMap<Int>(chunkSize: CGSize(width: 100, height: 100))

        map.insert(0, with: CGRect(x: 0, y: 100, width: 50, height: 0))
        map.insert(1, with: CGRect(x: 100, y: 0, width: 0, height: 50))
        map.insert(2, with: CGRect(x: 100, y: 100, width: 0, height: 0))
        XCTAssertEqual(map.count, 3)

        _ = map.query(CGRect(x: 0, y: 100, width: 100, height: 0))

        map.remove(value: 0)
        map.remove(value: 1)
        map.remove(value: 2)
        XCTAssertEqual(map.count, 0)
    }

    func testInsertExistingValueReplacesRect() {
        let map = ChunkedRectMap<Int>(chunkSize: CGSize(width: 100, height: 100))

        map.insert(0, with: CGRect(x: 0, y: 0, width: 50, height: 50))
        map.insert(0, with: CGRect(x: 0, y: 300, width: 50, height: 50))
        XCTAssertEqual(map.count, 1)

        XCTAssertEqual(map.query(CGRect(x: 0, y: 0, width: 100, height: 100)), [])
        XCTAssertEqual(map.query(CGRect(x: 0, y: 300, width: 100, height: 100)), [0])

        map.remove(value: 0)
        XCTAssertEqual(map.count, 0)
    }

    func testRemoveAllForgetsValues() {
        let map = ChunkedRectMap<Int>(chunkSize: CGSize(width: 100, height: 100))

        map.insert(0, with: CGRect(x: 0, y: 0, width: 50, height: 50))
        map.removeAll()
        XCTAssertEqual(map.count, 0)

        map.remove(value: 0)
        XCTAssertEqual(map.count, 0)
    }
}
