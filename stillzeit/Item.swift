//
//  Item.swift
//  stillzeit
//
//  Created by Lucas Tschirch on 14.08.26.
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
