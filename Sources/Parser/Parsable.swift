//
//  Parsable.swift
//  Parser
//
//  Created by Mark Onyschuk on 2020-01-28.
//  Copyright (C) 2019, 2020 NdimensionL, Inc. All Rights Reserved
//

import Foundation

/// A collection which can be *chunked* into pieces using a `Parser`
public protocol Parsable: Collection where Self.Element: Equatable {
    init(parsed subsequence: Self.SubSequence)
}

extension String: Parsable {
    public init(parsed subsequence: Self.SubSequence) {
        self.init(subsequence)
    }
}

extension Array: Parsable where Element: Equatable {
    public init(parsed subsequence: Self.SubSequence) {
        self.init(subsequence)
    }
}

