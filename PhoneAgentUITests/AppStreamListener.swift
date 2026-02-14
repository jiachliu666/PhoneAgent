//
//  AppStreamListener.swift
//  PhoneAgent
//
//  Created by Rounak Jain on 5/31/25.
//

import Network
import Foundation
import XCTest

public enum AppToTestMessage: Codable {
    case prompt(String)
    case apiKey(String)
}

class AppStreamListener {
    typealias AsyncMessageStream = AsyncStream<AppToTestMessage>
    private let listener: NWListener
    private var connections: [NWConnection] = []
    public let messages: AsyncMessageStream
    private let continuation: AsyncMessageStream.Continuation
    private let port: NWEndpoint.Port = 12345

    init() {
        do {
            var tempContinuation: AsyncMessageStream.Continuation!
            self.messages = AsyncStream { continuation in
                tempContinuation = continuation
            }
            self.continuation = tempContinuation
            // This channel is strictly app<->test on the same device/simulator.
            // Bind to loopback so we don't expose the port to the LAN.
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            parameters.prohibitedInterfaceTypes = [.wifi, .wiredEthernet, .cellular]
            listener = try NWListener(using: parameters, on: port)
        } catch {
            fatalError("Failed to create listener: \(error)")
        }
    }

    func start() {
        listener.stateUpdateHandler = { newState in
            print("Server state: \(newState)")
        }

        listener.newConnectionHandler = { [weak self] (newConnection) in
            guard Self.isLoopbackConnection(newConnection.endpoint) else {
                newConnection.cancel()
                return
            }
            self?.connections.append(newConnection)
            self?.setupReceive(on: newConnection)
            newConnection.start(queue: .main)
            print("Server accepted connection from \(String(describing: newConnection.endpoint))")
        }

        listener.start(queue: .main)
    }

    let decoder = JSONDecoder()

    private func setupReceive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
            if let data, !data.isEmpty, let message = try? self?.decoder.decode(AppToTestMessage.self, from: data) {
                // Publish the message via async sequence
                self?.continuation.yield(message)
            }
            if isComplete {
                connection.cancel()
                self?.continuation.finish()
                self?.connections.removeAll { $0 === connection }
            } else if let error = error {
                print("Server error: \(error)")
                connection.cancel()
                self?.continuation.finish()
                self?.connections.removeAll { $0 === connection }
            } else {
                self?.setupReceive(on: connection)
            }
        }
    }
}

private extension AppStreamListener {
    static func isLoopbackConnection(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let addr):
            return addr == IPv4Address.loopback
        case .ipv6(let addr):
            return addr == IPv6Address.loopback
        case .name(let name, _):
            return name == "localhost"
        @unknown default:
            return false
        }
    }
}
