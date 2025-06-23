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

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("视频参数设置")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最大比特率: \(store.maxBitrateBps) bps")
                        Slider(value: Binding(
                            get: { Double(store.maxBitrateBps) },
                            set: { store.maxBitrateBps = UInt32($0) }
                        ), in: 100_000...8_000_000, step: 50_000)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最小比特率: \(store.minBitrateBps) bps")
                        Slider(value: Binding(
                            get: { Double(store.minBitrateBps) },
                            set: { store.minBitrateBps = UInt32($0) }
                        ), in: 10_000...5_000_000, step: 10_000)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最大帧率: \(store.maxFramerateFps) fps")
                        Slider(value: Binding(
                            get: { Double(store.maxFramerateFps) },
                            set: { store.maxFramerateFps = UInt32($0) }
                        ), in: 5...60, step: 5)
                    }
                }
                
                Section {
                    Button("重置为默认值") {
                        store.maxBitrateBps = 300_000
                        store.minBitrateBps = 50_000
                        store.maxFramerateFps = 20
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("参数设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Custom UI Components
struct MainFunctionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isLoading: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: icon)
                            .font(.title2)
                    }
                }
                .frame(width: 24, height: 24)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [color, color.opacity(0.8)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .foregroundColor(.white)
            .cornerRadius(16)
            .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(isLoading)
        .scaleEffect(isLoading ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

struct DeviceCard: View {
    let device: EsDevice
    let isSelected: Bool
    let onTap: () -> Void
    let onPing: () -> Void
    @State private var onlineStatus: OnlineStatus = .unknown
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: onTap) {
                HStack(spacing: 16) {
                    VStack {
                        Image(systemName: "tv.fill")
                            .font(.title2)
                            .foregroundColor(isSelected ? .white : .blue)
                    }
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.blue : Color.blue.opacity(0.1))
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.deviceName)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(isSelected ? .white : .primary)
                        
                        Text("\(device.deviceIp):\(device.devicePort)")
                            .font(.caption)
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                onlineStatus = .searching
                onPing()
            }) {
                HStack(spacing: 4) {
                    if onlineStatus == .searching {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: onlineStatus == .online ? "wifi" : onlineStatus == .offline ? "wifi.slash" : "questionmark.circle")
                            .font(.caption)
                    }
                    Text(onlineStatus.des)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(onlineStatus == .online ? Color.green : onlineStatus == .offline ? Color.red : Color.orange)
                )
                .foregroundColor(.white)
            }
            .disabled(onlineStatus == .searching)
            .onReceive(NotificationCenter.default.publisher(for: .deviceOnlineStatusChanged)) { notification in
                if let deviceId = notification.userInfo?["deviceId"] as? String,
                   let status = notification.userInfo?["status"] as? OnlineStatus,
                   deviceId == device.id {
                    onlineStatus = status
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue : Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct EmptyDeviceView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("暂无发现设备")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("点击搜索设备按钮开始查找")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Main View
struct DeviceView: View {
    @EnvironmentObject var store: Store
    @State private var isSearching = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        
                        mainFunctionButtons
                        
                        deviceListSection
                        
                        connectionInfoSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
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
        .fullScreenCover(isPresented: $store.showCapture) {
            ContentView(device: store.selectDeive!, isScreen: store.isScreen, maxBitrateBps: Int(store.maxBitrateBps), minBitrateBps: Int(store.minBitrateBps), maxFramerateFps: Int(store.maxFramerateFps))
        }
        .sheet(isPresented: $store.showTestView) {
            TestDelegateView()
        }
        .sheet(isPresented: $store.showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .environmentObject(store)
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("HuanCapture演示")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue, .purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Text("Huan.Tv专业的屏幕投射解决方案")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
    }
    
    private var mainFunctionButtons: some View {
        VStack(spacing: 16) {
            Text("核心功能")
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 16) {
                MainFunctionButton(
                    title: "搜索设备",
                    icon: "magnifyingglass.circle.fill",
                    color: .blue,
                    isLoading: isSearching
                ) {
                    withAnimation {
                        isSearching = true
                    }
                    store.performAction(.searchDevice)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            isSearching = false
                        }
                    }
                }
                
                MainFunctionButton(
                    title: "摄像头",
                    icon: "camera.fill",
                    color: .green
                ) {
                    store.isScreen = false
                    store.performAction(.capture)
                }
                
                MainFunctionButton(
                    title: "录屏",
                    icon: "record.circle.fill",
                    color: .red
                ) {
                    store.isScreen = true
                    store.performAction(.capture)
                }
            }
            
            HStack(spacing: 16) {
                MainFunctionButton(
                    title: "测试销毁",
                    icon: "trash.circle.fill",
                    color: .orange
                ) {
                    store.showTestView = true
                }
                
                MainFunctionButton(
                    title: "参数设置",
                    icon: "gearshape.fill",
                    color: .purple
                ) {
                    store.showSettings = true
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 8)
    }
    
    private var deviceListSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("发现的设备")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(store.deiveList.count) 台设备")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
            
            if store.deiveList.isEmpty {
                EmptyDeviceView()
            } else {
                LazyVStack(spacing: 12) {
                     ForEach(store.deiveList, id: \.id) { device in
                         DeviceCard(
                             device: device,
                             isSelected: store.selectDeive?.id == device.id,
                             onTap: {
                                 withAnimation(.spring()) {
                                     store.selectDeive = device
                                 }
                             },
                             onPing: {
                                 let previousDevice = store.selectDeive
                                 store.selectDeive = device
                                 store.performAction(.ping)
                                 store.selectDeive = previousDevice
                             }
                         )
                     }
                 }
            }
        }
    }
    
    private var connectionInfoSection: some View {
        VStack(spacing: 12) {
            Text("连接信息")
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 8) {
                InfoRow(title: "本机IP", value: EsMessenger.shared.iPAddress ?? "未知")
                InfoRow(title: "选中设备", value: store.selectDeive?.deviceName ?? "未选中")
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        }
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
    @Published var isScreen: Bool = false
    @Published var showTestView: Bool = false
    @Published var showSettings: Bool = false
    @Published var maxBitrateBps: UInt32 = 300_000
    @Published var minBitrateBps: UInt32 = 50_000
    @Published var maxFramerateFps: UInt32 = 20

    init() {
        EsMessenger.shared.addDelegate(self)
        EsMessenger.shared.isDebugLogEnabled = true
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
                let isOnline = await EsMessenger.shared.checkDeviceOnline(device: deive, timeout: 10)
                let status: OnlineStatus = isOnline ? .online : .offline
                self.online = status
                
                // 发送通知更新特定设备的在线状态
                NotificationCenter.default.post(
                    name: .deviceOnlineStatusChanged,
                    object: nil,
                    userInfo: ["deviceId": deive.id, "status": status]
                )
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

extension Notification.Name {
    static let deviceOnlineStatusChanged = Notification.Name("deviceOnlineStatusChanged")
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

class TestDelegate: ObservableObject, MessengerCallback {
    @Published var messages: [String] = []
    
    init() {
        messages.append("TestDelegate 初始化")
        EsMessenger.shared.addDelegate(self)
        messages.append("已添加为EsMessenger代理")
    }
    
    deinit {
        messages.append("TestDelegate 销毁")
        EsMessenger.shared.removeDelegate(self)
        print("TestDelegate 已销毁，并从EsMessenger移除代理")
    }
    
    func onFindDevice(_ device: EsDevice) {
        messages.append("发现设备: \(device.deviceName)")
    }
    
    func onReceiveEvent(_ event: EsEvent) {
        messages.append("收到事件: \(event.des)")
    }
}

struct TestDelegateView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var testDelegate = TestDelegate()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("测试EsMessenger代理销毁")
                    .font(.headline)
                    .padding()
                
                Text("这个视图会在初始化时添加自己作为EsMessenger的代理，并在销毁时移除自己")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                List {
                    ForEach(testDelegate.messages, id: \.self) { message in
                        Text(message)
                            .padding(.vertical, 4)
                    }
                }
                .listStyle(InsetGroupedListStyle())
                
                Button(action: {
                    EsMessenger.shared.startDeviceSearch()
                }) {
                    Text("搜索设备")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
                Button(action: {
                    dismiss()
                }) {
                    Text("关闭视图 (触发deinit)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .navigationTitle("代理测试")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
