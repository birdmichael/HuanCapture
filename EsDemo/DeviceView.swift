//
//  DeviceView.swift
//  EsDemo
//
//  Created by BM on 4/28/25.
//

import SwiftUI
import es_cast_client_ios
import HuanCapture

enum Action: Hashable {
    static func == (lhs: Action, rhs: Action) -> Bool {
        lhs.name == rhs.name
    }

    case searchDevice
    case startApplication
    case closeApplication
    case querytop
    case queryApps
    case ping
    case capture
    case keybokard(ESRemoteControlKey)

    var name: String {
        switch self {
        case .searchDevice: return "搜索"
        case .startApplication: return "启动"
        case .closeApplication: return "关闭"
        case .querytop: return "查询顶层"
        case .queryApps: return "查询所有"
        case .keybokard(let key): return key.description
            case .capture: return "摄像头"
        case .ping:
            return "检测在线"
        }
    }
}

struct DeviceView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack {
            Text("当前IP: \(EsMessenger.shared.iPAddress ?? "")")
                .padding()

            Text("选中设备:\(store.selectDeive?.deviceName ?? "未选中")")

            ScrollView(.horizontal) {
                HStack {
                    ForEach(store.deiveList, id: \.id) { d in
                        Text(d.deviceName)
                            .padding(5)
                            .font(.body)
                            .background(Color.gray)
                            .foregroundColor(Color.white)
                            .cornerRadius(8)
                            .onTapGesture {
                                store.selectDeive = d
                            }
                    }
                }
                .padding(.horizontal)
            }

            ScrollView {
                ScrollViewReader { scrollViewProxy in
                    LazyVStack {
                        ForEach(Array(store.messageList.enumerated()), id: \.offset) { index, msg in
                            Text("[\(msg.deviceIp):\(msg.devicePort)]:\(msg.des)")
                                .font(.caption2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                                .id(index)
                        }
                    }
                    .onChange(of: store.messageList.count, perform: { _ in
                        withAnimation {
                            scrollViewProxy.scrollTo(store.messageList.count - 1)
                        }
                    })
                }
            }
            .frame(maxWidth: .infinity)

            LazyVGrid(columns: .init(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach([Action.searchDevice, .startApplication, .closeApplication, .capture, .queryApps, .ping], id: \.self) { action in
                    Button(action: {
                        store.performAction(action)
                    }) {
                        if action == .ping {
                            Text(store.online.des)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .foregroundColor(Color.white)
                                .cornerRadius(20)
                        } else {
                            Text(action.name)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .foregroundColor(Color.white)
                                .cornerRadius(20)
                        }
                    }
                }
            }
            .padding(.horizontal)

            VStack {
                ButtonRow(buttons: [.custom(name: "关机", value: 0), .up, .volumeUp])
                ButtonRow(buttons: [.left, .ok, .right])
                ButtonRow(buttons: [.back, .down, .volumeDown])
                ButtonRow(buttons: [.menu, .custom(name: "直播", value: 100), .home])
            }

            Spacer()
        }
        .alert("请输入包名", isPresented: $store.isShowingAlert) {
            TextField("pkg", text: $store.userInput)
            Button("发送") {
                store.performAction(store.lastAction!)
            }
            Button("取消", role: .cancel) {
                store.userInput = ""
            }
        }
        .environmentObject(store)
        
    }
}

struct ButtonRow: View {
    let buttons: [ESRemoteControlKey]

    var body: some View {
        HStack {
            ForEach(buttons, id: \.description) { button in
                RemoteButtonView(button: button)
            }
        }
    }
}

struct RemoteButtonView: View {
    let button: ESRemoteControlKey
    @EnvironmentObject var store: Store

    var body: some View {
        Button(action: {
            store.performAction(.keybokard(button))
        }) {
            Text(button.description)
                .frame(width: 80, height: 80)
                .background(Color.gray)
                .foregroundColor(.white)
                .cornerRadius(40)
        }
    }
}

struct RemoteButton: Identifiable {
    let id = UUID()
    let title: String
    let keyValue: Int
}

class Store: ObservableObject, MessengerCallback {
    @Published var deiveList: [EsDevice] = []
    @Published var messageList: [EsEvent] = []
    @Published var isShowingAlert = false
    @Published var userInput = ""
    @Published var lastAction: Action?
    @Published var selectDeive: EsDevice?
    @Published var online: OnlineStatus = .unknown
    @Published var showCapture: Bool = false

    init() {
        EsMessenger.shared.addDelegate(self)
        ESConfig.device.idfa("idfa_is_31231")
        ESConfig.device.custom("some_key", value: "some_value")
        ESConfig.device.custom("some_key1", value: "some_value1")

        EsMessenger.shared.config.device.idfa("idfa_is_31231")
    }

    func onFindDevice(_ device: EsDevice) {
        if !deiveList.contains(where: { $0.id == device.id }) {
            deiveList.append(device)
        }
    }

    func onReceiveEvent(_ event: EsEvent) {
        messageList.append(event)
    }

    func performAction(_ action: Action) {
        lastAction = action
        if action == .searchDevice {
            EsMessenger.shared.startDeviceSearch()
        }

        guard let deive = selectDeive else {
            return
        }
        switch action {
        case .searchDevice:
            break
        case .startApplication:
            if userInput.isEmpty {
                isShowingAlert = true
            } else {
                EsMessenger.shared
                    .sendDeviceCommand(device: deive, action: .makeStartEs(pkg: userInput))
                userInput = ""
            }

        case .closeApplication:
            if userInput.isEmpty {
                isShowingAlert = true
            } else {
                EsMessenger.shared.sendDeviceCommand(device: deive, action: .makeCloseApp(pkgs: userInput))
                userInput = ""
            }
        case .queryApps:
            EsMessenger.shared.sendDeviceCommand(device: deive, action: .makeQueryApps())
        case .querytop:
            EsMessenger.shared.sendDeviceCommand(device: deive, action: .makeQueryTopApp())
        case .keybokard(let key):
            EsMessenger.shared.sendDeviceCommand(device: deive, action: .makeRemoteControl(key: key))
        case .ping:
            online = .searching
            Task { @MainActor in
                let online = await EsMessenger.shared.checkDeviceOnline(device: deive, timeout: 10)
                self.online = online ? .online : .offline
            }
        case .capture:
            Task{ @MainActor in
                showCapture.toggle()
            }
        }
    
    }
}

extension EsEvent {
    var des: String { data.jsonString() ?? "" }
}

extension Dictionary {
    func jsonString(prettify: Bool = false) -> String? {
        guard JSONSerialization.isValidJSONObject(self) else { return nil }
        let options = (prettify == true) ? JSONSerialization.WritingOptions.prettyPrinted : JSONSerialization
            .WritingOptions()
        guard let jsonData = try? JSONSerialization.data(withJSONObject: self, options: options) else { return nil }
        return String(data: jsonData, encoding: .utf8)
    }
}

enum OnlineStatus {
    case unknown
    case online
    case offline
    case searching

    var des: String {
        switch self {
        case .unknown:
            return "检查状态"
        case .online:
            return "状态:在线"
        case .offline:
            return "状态:离线"
        case .searching:
            return "查询中"
        }
    }
}

#Preview {
    DeviceView()
}
