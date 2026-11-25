//
//  OpenAILiveExample.swift
//  OpenAILive
//

import Foundation
import SwitchboardSDK

protocol OpenAILiveExampleDelegate: AnyObject {
    /// A piece of what `speaker` ("You" or "Assistant") said.
    func transcript(speaker: String, delta: String)

    /// A line about the session or a tool call.
    func status(_ text: String)
}

/// A voice conversation with OpenAI's realtime model, through the OpenAI.Live node.
///
/// Each `start()` creates the engine from OpenAILiveExample.json and starts a new conversation;
/// `stop()` ends it. The assistant's tools (play and pause the music) are answered here,
/// in `handleToolCall`.
class OpenAILiveExample {
    /// Called on the main thread.
    weak var delegate: OpenAILiveExampleDelegate?

    private(set) var isRunning = false

    private let liveNode = "liveNode"
    private let musicPlayerNode = "musicPlayerNode"
    private let musicURL =
        "https://switchboard-sdk-public.s3.dualstack.us-east-1.amazonaws.com/assets/audio/music/elevator-music-stereo.mp3"
    // States in which the music is open, so play resumes it instead of loading it again.
    private let openMusicStates: Set<String> = ["connecting", "buffering", "ready"]

    private var engineID: String?
    private var listenerIDs: [NSNumber] = []
    private var connectedBefore = false

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        if appID.isEmpty || appSecret.isEmpty {
            status("Set your Switchboard app's ID and secret in App.swift. Register an app at console.switchboard.audio/register.")
            return false
        }
        guard let path = Bundle.main.path(forResource: "OpenAILiveExample", ofType: "json"),
              let json = try? String(contentsOfFile: path, encoding: .utf8)
        else {
            status("Couldn't read OpenAILiveExample.json")
            return false
        }

        let createResult = Switchboard.createEngine(withJSON: json)
        guard createResult.success, let value = createResult.value else {
            status("Failed to create the engine: \(message(createResult.error))")
            return false
        }
        let id = value as String
        engineID = id
        connectedBefore = false
        addEventListeners()

        let startResult = Switchboard.callAction(withObject: id, actionName: "start", params: nil)
        if !startResult.success {
            status("Failed to start the engine: \(message(startResult.error))")
            stop()
            return false
        }
        isRunning = true
        status("Connecting…")
        return true
    }

    func stop() {
        guard let engineID else { return }
        Switchboard.callAction(withObject: engineID, actionName: "stop", params: nil)
        for listenerID in listenerIDs {
            Switchboard.removeEventListener(liveNode, listenerID: listenerID)
        }
        listenerIDs.removeAll()
        Switchboard.destroyEngine(withObjectID: engineID)
        self.engineID = nil
        isRunning = false
    }

    private func addEventListeners() {
        func listen(_ eventName: String, _ handler: @escaping ([AnyHashable: Any]) -> Void) {
            // The callback gets the whole event (id, name, objectURI, timestamp); its own fields are under "data".
            let result = Switchboard.addEventListener(liveNode, eventName: eventName) { event in
                handler(event["data"] as? [AnyHashable: Any] ?? [:])
            }
            if let listenerID = result.value {
                listenerIDs.append(listenerID)
            }
        }

        // Transcript
        listen("inputTranscriptDelta") { [weak self] data in
            self?.transcript("You", data["delta"] as? String ?? "")
        }
        listen("outputTranscriptDelta") { [weak self] data in
            self?.transcript("Assistant", data["delta"] as? String ?? "")
        }

        // Tool calls. Events arrive on an SDK thread, which may answer right away.
        listen("toolCall") { [weak self] data in
            guard let self,
                  let callID = data["callId"] as? String,
                  let name = data["name"] as? String
            else { return }
            let output = handleToolCall(name)
            status(output.ok ? "[\(name)]" : "[\(name) failed: \(output.json)]")

            let answer = output.ok
                ? Switchboard.callAction(
                    withObject: liveNode,
                    actionName: "submitToolResult",
                    params: ["callId": callID, "outputJson": output.json]
                )
                : Switchboard.callAction(
                    withObject: liveNode,
                    actionName: "submitToolError",
                    params: ["callId": callID, "errorJson": output.json]
                )
            if !answer.success {
                status("[Failed to answer \(name): \(message(answer.error))]")
            }
        }

        // Session state
        listen("sessionStarted") { [weak self] _ in
            guard let self else { return }
            status(connectedBefore ? "Connected." : "Connected. Start talking.")
            connectedBefore = true
        }
        listen("sessionPaused") { [weak self] _ in
            self?.status("Standby: paused after 15 s of quiet. Speak to resume.")
        }
        listen("sessionResumed") { [weak self] _ in
            self?.status("Standby: resumed.")
        }
        listen("sessionIdle") { [weak self] _ in
            self?.status("Idle: the session closed after 30 s of quiet. Speak to continue the conversation.")
        }
        listen("sessionWoken") { [weak self] _ in
            self?.status("Idle: reopened.")
        }
        listen("sessionDisconnected") { [weak self] _ in
            self?.status("Connection lost. Reconnecting.")
        }
        listen("error") { [weak self] data in
            self?.status("Error: \(data["type"] ?? "") \(data["code"] ?? ""): \(data["message"] ?? "")")
        }
    }

    // MARK: - Tools

    private struct ToolOutput {
        let ok: Bool
        let json: String
    }

    private func handleToolCall(_ name: String) -> ToolOutput {
        switch name {
        case "play_music":
            return playMusic()
        case "pause_music":
            return musicResult(callMusicPlayer("pause"), playing: false)
        default:
            return toolError("Unknown tool: \(name)")
        }
    }

    // Resumes the track if it's open (paused), otherwise loads it, which starts it since the player has autoPlay.
    private func playMusic() -> ToolOutput {
        let state = Switchboard.getValueForKey("state", object: musicPlayerNode).value as? String
        if let state, openMusicStates.contains(state) {
            return musicResult(callMusicPlayer("play"), playing: true)
        }
        return musicResult(callMusicPlayer("load", params: ["url": musicURL]), playing: true)
    }

    private func callMusicPlayer(_ action: String, params: [String: Any]? = nil) -> SBResult<AnyObject> {
        Switchboard.callAction(withObject: musicPlayerNode, actionName: action, params: params)
    }

    private func musicResult(_ result: SBResult<AnyObject>, playing: Bool) -> ToolOutput {
        result.success ? ToolOutput(ok: true, json: jsonString(["playing": playing])) : toolError(message(result.error))
    }

    private func toolError(_ message: String) -> ToolOutput {
        ToolOutput(ok: false, json: jsonString(["error": message]))
    }

    private func jsonString(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }

    private func message(_ error: Error?) -> String {
        error?.localizedDescription ?? "Unknown error"
    }

    // MARK: - UI updates go to the main thread.

    private func transcript(_ speaker: String, _ delta: String) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.transcript(speaker: speaker, delta: delta)
        }
    }

    private func status(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.status(text)
        }
    }
}
