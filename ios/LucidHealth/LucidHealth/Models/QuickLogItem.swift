import Foundation

struct QuickLogItem: Identifiable, Codable {
    let id: String
    let name: String
    let icon: String        // SF Symbol name
    let kcal: Int
    let novaClass: Int
    let mindTags: [String]
}

extension QuickLogItem {
    static let defaults: [QuickLogItem] = [
        QuickLogItem(id: "espresso",   name: "Espresso",   icon: "cup.and.saucer.fill", kcal: 3,   novaClass: 1, mindTags: []),
        QuickLogItem(id: "cappuccino", name: "Cappuccino", icon: "cup.and.saucer",      kcal: 80,  novaClass: 2, mindTags: []),
        QuickLogItem(id: "water",      name: "Wasser",     icon: "drop.fill",           kcal: 0,   novaClass: 1, mindTags: []),
        QuickLogItem(id: "wine",       name: "Glas Wein",  icon: "wineglass.fill",      kcal: 125, novaClass: 1, mindTags: ["alcohol"]),
        QuickLogItem(id: "beer",       name: "Bier 0.5L",  icon: "mug.fill",            kcal: 215, novaClass: 1, mindTags: ["alcohol"]),
        QuickLogItem(id: "banana",     name: "Banane",     icon: "leaf.fill",           kcal: 105, novaClass: 1, mindTags: ["fruit"]),
        QuickLogItem(id: "apple",      name: "Apfel",      icon: "leaf.fill",           kcal: 95,  novaClass: 1, mindTags: ["fruit"])
    ]
}
