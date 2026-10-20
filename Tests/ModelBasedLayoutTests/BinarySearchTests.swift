//
//  BinarySearchTests.swift
//  ModelBasedLayoutTests
//
//  Created by Matteo Ludwig on 21.10.26.
//

import XCTest
@testable import ModelBasedLayout


final class BinarySearchTests: XCTestCase {

    func testComparisonSearchWithoutMatchReturnsNil() {
        let values = [1, 3, 5, 7]

        func search(_ searched: Int) -> Int? {
            values.binarySearch { value in
                if value < searched {
                    return .beforeSearched
                } else if value > searched {
                    return .afterSearched
                }
                return .equalToSearched
            }
        }

        XCTAssertEqual(search(5), 2)
        XCTAssertEqual(search(0), nil)
        XCTAssertEqual(search(4), nil)
        XCTAssertEqual(search(8), nil)
    }
}
