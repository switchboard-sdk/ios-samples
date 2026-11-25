import SwiftUI
import SwitchboardOpenAI
import SwitchboardSDK
import SwitchboardSileroVAD

// Your Switchboard app's ID and secret. Register an app at https://console.switchboard.audio/register.
let appID = ""
let appSecret = ""

@main
struct OpenAILiveApp: App {

    init() {
        // OpenAI Extension
        SBOpenAIExtension.loadExtension()

        // SileroVAD Extension, for idle mode
        SBSileroVADExtension.loadExtension()

        // Init SDK
        let initConfig: [String: Any] = [
            "appID": appID,
            "appSecret": appSecret,
            "extensions": [
                "OpenAI": [:],
                "Silero": [:],
            ],
        ]
        let result = Switchboard.initialize(withConfig: initConfig)
        if !result.success {
            fatalError("Switchboard SDK initialization failed: \(result.error?.localizedDescription ?? "")")
        }
    }

    var body: some Scene {
        WindowGroup {
            OpenAILiveExampleView()
        }
    }
}
