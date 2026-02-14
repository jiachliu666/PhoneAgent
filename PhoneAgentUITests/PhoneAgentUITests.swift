//
//  PhoneAgentUITests.swift
//  PhoneAgentUITests
//
//  Created by Rounak Jain on 5/30/25.
//

import Darwin
import Foundation
import UserNotifications
import XCTest

final class PhoneAgent: XCTestCase {
    private enum Mode: String {
        case rpc
        case loop
    }

    private var mode: Mode {
        let raw = (ProcessInfo.processInfo.environment["PHONEAGENT_MODE"] ?? "rpc")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return Mode(rawValue: raw) ?? .rpc
    }

    let appListener = AppStreamListener()
    var task: Task<Void, Never>?

    var api: OpenAIService?
    let notificationCenter = UNUserNotificationCenter.current()
    var lastRequest: OpenAIRequest?
    var app: XCUIApplication?
    private var rpcServer: SimulatorRPCServer?

    override func setUpWithError() throws {
        switch mode {
        case .rpc:
            continueAfterFailure = false
            // Defer launching any app until the RPC server is ready so callers can optionally
            // start directly in a specific target app (or skip the initial launch entirely).
            app = nil
        case .loop:
            continueAfterFailure = true
            appListener.start()

            let app = XCUIApplication()
            app.launch()
            self.app = app

            notificationCenter.requestNotificationPermission()
            notificationCenter.delegate = self
        }
    }

    override func tearDownWithError() throws {
        task?.cancel()
        task = nil

        api = nil
        lastRequest = nil

        rpcServer?.stop()
        rpcServer = nil
        app = nil
    }

    @MainActor
    func testMain() async throws {
        switch mode {
        case .rpc:
            try await runRPCServer()
        case .loop:
            try await runLoop()
        }
    }

    @MainActor
    private func runRPCServer() async throws {
        let stopExpectation = expectation(description: "stop rpc server")
        let requestedPort = ProcessInfo.processInfo.environment["PHONEAGENT_RPC_PORT"]
            .flatMap(UInt16.init) ?? 45678
        let token = try resolveRPCToken()

        let server = try SimulatorRPCServer(
            requestedPort: requestedPort,
            expectedToken: token,
            onReady: { port in
                print("PHONEAGENT_RPC_PORT=\(port)")
                fflush(stdout)
            },
            onStop: {
                stopExpectation.fulfill()
            },
            commandHandler: { [weak self] method, params in
                guard let self else { throw PhoneAgent.Error.serverShutDown }
                return try await MainActor.run {
                    try self.handleRPC(method: method, params: params)
                }
            }
        )

        rpcServer = server
        server.start()

        // Launch the host app so `get_tree` works immediately without a prior `open_app` call.
        let app = XCUIApplication()
        app.launch()
        self.app = app

        await fulfillment(of: [stopExpectation], timeout: 60 * 60 * 6)

        server.stop()
    }

    private func resolveRPCToken() throws -> String {
        let raw = (ProcessInfo.processInfo.environment["PHONEAGENT_RPC_TOKEN"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw NSError(
                domain: "PhoneAgent",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing required env var PHONEAGENT_RPC_TOKEN"]
            )
        }
        return raw
    }

    @MainActor
    func runLoop() async throws {
        for await prompt in appListener.messages {
            switch prompt {
            case .apiKey(let apiKey):
                api = OpenAIService(with: apiKey)
            case .prompt(let prompt):
                guard task == nil || task?.isCancelled == false else { continue }
                task = Task {
                    do {
                        try await submit(prompt)
                    } catch {
                        print("Error processing prompt: \(error)")
                    }
                }
            }
        }
    }


    func testDecoding() throws {
        let rawResponse =
        """
        {
          "id": "resp_683b49b0916c819b9db77fc68c0ed429016e90871fbf8114",
          "object": "response",
          "created_at": 1748715952,
          "status": "completed",
          "background": false,
          "error": null,
          "incomplete_details": null,
          "instructions": null,
          "max_output_tokens": null,
          "model": "gpt-4.1-2025-04-14",
          "output": [
            {
              "id": "fc_683b49b19d00819bbb0c6ca4ab088c85016e90871fbf8114",
              "type": "function_call",
              "status": "completed",
              "arguments": "{\\\"bundle_identifier\\\":\\\"com.apple.Preferences\\\"}",
              "call_id": "call_VduQZcKYvlyfrY5SINGzVrTd",
              "name": "openApp"
            },
            {
              "id": "fc_683b49b636f4819ba3b969b0b0085edf016e90871fbf8114",
              "type": "function_call",
              "status": "completed",
              "arguments": "{}",
              "call_id": "call_BvRXpELYGUyPqoQbyVnB69xC",
              "name": "fetchAccessibilityTree"
            },
            {
              "id": "msg_683b5224ecb8819baa03843bc12f514603d927c115159226",
              "type": "message",
              "status": "completed",
              "content": [
                {
                  "type": "output_text",
                  "annotations": [],
                  "text": "Settings is now open. What would you like to do next? (For example: adjust Wi-Fi, Bluetooth, display, notifications, etc.)"
                }
              ],
              "role": "assistant"
            }
          ],
          "previous_response_id": "resp_683b49b0916c819b9db77fc68c0ed429016e90871fbf8114"
        }
        """
        let response = try JSONDecoder.shared.decode(Response.self, from: .init(rawResponse.utf8))
        XCTAssertEqual(
            response,
            Response(
                id: "resp_683b49b0916c819b9db77fc68c0ed429016e90871fbf8114",
                output: [.functionCall(
                            id:  "call_VduQZcKYvlyfrY5SINGzVrTd",
                            .openApp(
                                bundleIdentifier: "com.apple.Preferences"
                            )
                        ),
                         .functionCall(
                            id: "call_BvRXpELYGUyPqoQbyVnB69xC",
                            .fetchAccessibilityTree
                         ),
                         .message(.init(content: [
                            .init(type: .outputText, text: "Settings is now open. What would you like to do next? (For example: adjust Wi-Fi, Bluetooth, display, notifications, etc.)")
                         ]))]
            )
        )
    }
}

extension UNUserNotificationCenter {
    func requestNotificationPermission() {
        requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Request authorization failed: \(error.localizedDescription)")
            }

            if granted {
                print("Notification permission granted.")
            } else {
                print("Notification permission denied.")
            }
        }
    }
}
