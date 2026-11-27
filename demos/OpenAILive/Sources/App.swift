import SwiftUI
import SwitchboardOpenAI
import SwitchboardSDK
import SwitchboardSileroVAD

@main
struct OpenAILiveApp: App {

    init() {
        // OpenAI Extension
        SBOpenAIExtension.loadExtension()

        // SileroVAD Extension, for idle mode
        SBSileroVADExtension.loadExtension()

        // Init SDK. OpenAI Live needs your own Switchboard app: register one at
        // https://console.switchboard.audio/register and put its appID and appSecret here.
        let initConfig: [String: Any] = [
            "appID": "demo",
            "appSecret": "demo",
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
