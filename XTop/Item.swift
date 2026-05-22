//
//  Item.swift
//  XTop
//
//  Created by harsh vishwakarma on 22/05/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
