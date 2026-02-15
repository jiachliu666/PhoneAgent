//
//  ContentView.swift
//  PhoneAgent
//
//  Created by Rounak Jain on 5/30/25.
//

import SwiftUI
import Security

struct ContentView: View {
    enum AppState {
        case enterAPIKey
        case prompt(String)
    }

    @State private var state: AppState = KeychainHelper.load().map { .prompt($0) } ?? .enterAPIKey
    let rpcClient: PhoneAgentRPCClient

    var body: some View {
        switch state {
        case .enterAPIKey:
            EnterAPIKeyView { key in
                KeychainHelper.save(key: key)
                state = .prompt(key)
            }
        case .prompt(let key):
            PromptView(rpcClient: rpcClient, deleteKey: deleteKey)
                .onAppear {
                    Task {
                        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        await rpcClient.setOpenAIAPIKey(trimmed)
                    }
                }
        }
    }

    private func deleteKey() {
        KeychainHelper.delete()
        state = .enterAPIKey
    }
}
