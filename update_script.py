import re
import sys

with open("ContentView.swift", "r") as f:
    content = f.read()

# Replace variables in IslandModel
search1 = r'(@Published var autoCloseBehavior: AutoCloseBehavior = .immediate\n    @Published var isHoverExpanded: Bool = false\n    var hoverCloseTask: Task<Void, Never>\? = nil)'
replace1 = r'\1\n\n    @Published var showAirPodsLocalization: Bool = false\n    @Published var showControlCenter: Bool = false\n    @Published var showMusic: Bool = false\n    @Published var showPhone: Bool = false\n    @Published var showNotifications: Bool = false\n    @Published var showAirDrop: Bool = false'
content = re.sub(search1, replace1, content)

# Replace SystemControlsView section
search2 = r'Section\(header: Text\("Hardware Integrations"\)\) \{ HStack \{ Image\(systemName: "airpodspro"\)\.foregroundStyle\(\.secondary\)\.frame\(width: 24\); Toggle\("Connect AirPods", isOn: \$model\.airPodsConnected\) \} \}'
replace2 = '''Section(header: Text("Visible Items"), footer: Text("Some items require permission.")) {
        HStack { Image(systemName: "airpodspro").frame(width: 24); Toggle("AirPods Localization", isOn: $model.showAirPodsLocalization) }
        HStack { Image(systemName: "switch.2").frame(width: 24); Toggle("Control Center Controls", isOn: $model.showControlCenter) }
        HStack { Image(systemName: "music.note").frame(width: 24); Toggle("Music", isOn: $model.showMusic) }
        HStack { Image(systemName: "phone").frame(width: 24); Toggle("Phone", isOn: $model.showPhone) }
        HStack { Image(systemName: "bell").frame(width: 24); Toggle("Notifications", isOn: $model.showNotifications) }
        HStack { Image(systemName: "airdrop").frame(width: 24); Toggle("AirDrop", isOn: $model.showAirDrop) }
    }'''
content = content.replace('Section(header: Text("Hardware Integrations")) { HStack { Image(systemName: "airpodspro").foregroundStyle(.secondary).frame(width: 24); Toggle("Connect AirPods", isOn: $model.airPodsConnected) } }', replace2)

with open("ContentView.swift", "w") as f:
    f.write(content)
print("Updated ContentView.swift successfully")
