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
/// in `runTool`.
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

    func start() {
        if isRunning { return }
        if appID.isEmpty || appSecret.isEmpty {
            status("Set your Switchboard app's ID and secret in App.swift. Register an app at console.switchboard.audio/register.")
            return
        }
        guard let path = Bundle.main.path(forResource: "OpenAILiveExample", ofType: "json"),
              let json = try? String(contentsOfFile: path, encoding: .utf8)
        else {
            status("Couldn't read OpenAILiveExample.json")
            return
        }

        let createResult = Switchboard.createEngine(withJSON: json)
        guard createResult.success, let value = createResult.value else {
            status("Failed to create the engine: \(errorText(createResult.error))")
            return
        }
        let id = value as String
        engineID = id
        addEventListeners()

        let startResult = Switchboard.callAction(withObject: id, actionName: "start", params: nil)
        if !startResult.success {
            status("Failed to start the engine: \(errorText(startResult.error))")
            stop()
            return
        }
        isRunning = true
        status("Connecting…")
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
            let answer: SBResult<AnyObject>
            if let error = runTool(name) {
                status("[\(name) failed: \(error)]")
                answer = Switchboard.callAction(
                    withObject: liveNode,
                    actionName: "submitToolError",
                    params: ["callId": callID, "errorJson": jsonString(["error": error])]
                )
            } else {
                status("[\(name)]")
                answer = Switchboard.callAction(
                    withObject: liveNode,
                    actionName: "submitToolResult",
                    params: ["callId": callID, "outputJson": #"{"ok":true}"#]
                )
            }
            if !answer.success {
                status("[Failed to answer \(name): \(errorText(answer.error))]")
            }
        }

        // Session state
        listen("sessionStarted") { [weak self] data in
            self?.status(data["continued"] as? Bool == true ? "Connected." : "Connected. Start talking.")
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
        listen("sessionDisconnected") { [weak self] data in
            self?.status(
                data["reconnecting"] as? Bool == true
                    ? "Connection lost. Reconnecting."
                    : "Session refused. Press Stop, then Start to try again."
            )
        }
        listen("error") { [weak self] data in
            self?.status("Error: \(data["type"] ?? "") \(data["code"] ?? ""): \(data["message"] ?? "")")
        }
    }

    // MARK: - Tools

    /// Runs a tool: nil when it worked, otherwise the error.
    private func runTool(_ name: String) -> String? {
        let result: SBResult<AnyObject>
        switch name {
        case "play_music":
            result = playMusic()
        case "pause_music":
            result = callMusicPlayer("pause")
        default:
            return "Unknown tool: \(name)"
        }
        return result.success ? nil : errorText(result.error)
    }

    // Resumes the track if it's open (paused), otherwise loads it, which starts it: the player plays what it loads.
    private func playMusic() -> SBResult<AnyObject> {
        let state = Switchboard.getValueForKey("state", object: musicPlayerNode).value as? String
        if let state, openMusicStates.contains(state) {
            return callMusicPlayer("play")
        }
        return callMusicPlayer("load", params: ["url": musicURL])
    }

    private func callMusicPlayer(_ action: String, params: [String: Any]? = nil) -> SBResult<AnyObject> {
        Switchboard.callAction(withObject: musicPlayerNode, actionName: action, params: params)
    }

    private func jsonString(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }

    private func errorText(_ error: Error?) -> String {
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
