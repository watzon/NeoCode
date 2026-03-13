//
//  Item.swift
//  NeoCode
//
//  Created by Chris W on 3/13/26.
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
