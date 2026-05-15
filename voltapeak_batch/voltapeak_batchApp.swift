//
//  voltapeak_batchApp.swift
//  voltapeak_batch
//
//  Point d'entrée SwiftUI : fenêtre principale, taille initiale alignée sur
//  la version Tkinter Python (~700×500).
//

import SwiftUI

@main
struct voltapeak_batchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 720, height: 520)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
