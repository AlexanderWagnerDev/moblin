import AVFAudio
import UIKit

class AudioProvider: ObservableObject {
    @Published var showing = false
    @Published var level: Float = defaultAudioLevel
    @Published var numberOfChannels: Int = 0
}

extension Model {
    func reloadAudioSession() {
        teardownAudioSession()
        setupAudioSession()
        media.attachDefaultAudioDevice(builtinDelay: database.debug.builtinAudioAndVideoDelay)
    }

    func setupAudioSession() {
        let bluetoothOutputOnly = database.debug.bluetoothOutputOnly
        netStreamLockQueue.async {
            let session = AVAudioSession.sharedInstance()
            do {
                let bluetoothOption: AVAudioSession.CategoryOptions
                if bluetoothOutputOnly {
                    bluetoothOption = .allowBluetoothA2DP
                } else {
                    bluetoothOption = .allowBluetooth
                }
                try session.setCategory(
                    .playAndRecord,
                    options: [.mixWithOthers, bluetoothOption, .defaultToSpeaker]
                )
                try session.setActive(true)
            } catch {
                logger.error("app: Session error \(error)")
            }
            self.setAllowHapticsAndSystemSoundsDuringRecording()
        }
    }

    func teardownAudioSession() {
        netStreamLockQueue.async {
            do {
                try AVAudioSession.sharedInstance().setActive(false)
            } catch {
                logger.info("Failed to stop audio session with error: \(error)")
            }
        }
    }

    @objc func systemVolumeDidChange(notification: NSNotification) {
        DispatchQueue.main.async {
            self.handleSystemVolumeDidChange(notification: notification)
        }
    }

    private func handleSystemVolumeDidChange(notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let volume = userInfo["Volume"] as? Float,
              let reason = userInfo["Reason"] as? String,
              let sequenceNumber = userInfo["SequenceNumber"] as? Int
        else {
            return
        }
        // For some reason two similar notifications are received. Not sure how to distinguish
        // them from each other.
        guard sequenceNumber != latestVolumeChangeSequenceNumber else {
            return
        }
        latestVolumeChangeSequenceNumber = sequenceNumber
        if reason == "ExplicitVolumeChange", database.selfieStick.buttonEnabled, isAppActive {
            if initialVolume == nil {
                initialVolume = volume
            }
            guard let initialVolume else {
                return
            }
            if volume != initialVolume {
                setSystemVolume(initialVolume)
                switchToNextSceneRoundRobin()
            } else if isVolumeMinOrMax(volume), latestSetVolumeTime.duration(to: .now) > .seconds(1) {
                switchToNextSceneRoundRobin()
            }
        } else {
            initialVolume = volume
        }
    }

    private func isVolumeMinOrMax(_ volume: Float) -> Bool {
        return volume == 0 || volume == 1
    }

    private func setSystemVolume(_ volume: Float) {
        if let volumeSlider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            // Can remove delay?
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.latestSetVolumeTime = .now
                volumeSlider.value = volume
            }
        }
    }

    @objc func handleAudioRouteChange(notification _: Notification) {
        // logger.info("xxx route change active: \(getActiveAudioSessionMic()?.name ?? "-")")
        updateMicsList()
        switchMicIfNeeded()
    }

    private func getActiveAudioSessionMic() -> SettingsMicsMic? {
        guard let inputPort = AVAudioSession.sharedInstance().currentRoute.inputs.first else {
            return nil
        }
        var newMic: SettingsMicsMic?
        if let dataSource = inputPort.preferredDataSource {
            var name: String
            var builtInMicOrientation: SettingsMic?
            if inputPort.portType == .builtInMic {
                name = dataSource.dataSourceName
                builtInMicOrientation = getBuiltInMicOrientation(orientation: dataSource.orientation)
            } else {
                name = "\(inputPort.portName): \(dataSource.dataSourceName)"
            }
            newMic = SettingsMicsMic()
            newMic!.name = name
            newMic!.inputUid = inputPort.uid
            newMic!.dataSourceId = dataSource.dataSourceID.intValue
            newMic!.builtInOrientation = builtInMicOrientation
        } else if inputPort.portType != .builtInMic {
            newMic = SettingsMicsMic()
            newMic!.name = inputPort.portName
            newMic!.inputUid = inputPort.uid
        }
        return newMic
    }

    func switchMicIfNeeded() {
        if database.mics.autoSwitch {
            autoSwitchMicIfNeeded()
        } else if currentMic.isAudioSession() {
            if getActiveAudioSessionMic() != currentMic {
                selectMicDefault(mic: currentMic)
            }
        }
    }

    private func autoSwitchMicIfNeeded() {
        // logger.info("xxx autoSwitchMicIfNeeded current mic \(currentMic.name)")
        if currentMic.isAudioSession(),
           currentMic.connected,
           let activeMic = getActiveAudioSessionMic(),
           getMicPriority(mic: activeMic) < getMicPriority(mic: currentMic)
        {
            // logger.info("xxx using current audio session mic again active \(activeMic.name) current
            // \(currentMic.name)")
            selectMicDefault(mic: currentMic)
        } else if let highestPrioMic = getHighestPriorityConnectedMic() {
            // logger.info("xxx highest prio \(highestPrioMic.name) active \(getActiveAudioSessionMic()?.name)")
            if highestPrioMic.isAudioSession() {
                if getActiveAudioSessionMic() != currentMic {
                    selectMicDefault(mic: highestPrioMic)
                    makeMicChangeToast(name: highestPrioMic.name)
                }
            } else if highestPrioMic != currentMic {
                selectMic(mic: highestPrioMic)
                makeMicChangeToast(name: highestPrioMic.name)
            }
        }
    }

    private func getMicPriority(mic: SettingsMicsMic) -> Int {
        if let priority = database.mics.mics.firstIndex(where: { $0.id == mic.id }) {
            return -priority
        } else {
            return Int.min
        }
    }

    private func getHighestPriorityConnectedMic() -> SettingsMicsMic? {
        return database.mics.mics.first(where: { $0.connected })
    }

    private func makeMicChangeToast(name: String) {
        makeToast(title: name)
    }

    private func micHasHigherPriorityThanCurrent(mic: SettingsMicsMic) -> Bool {
        for databaseMic in database.mics.mics {
            // logger.info("xxx micHasHigherPriorityThanCurrent \(databaseMic.name) \(databaseMic.connected)")
            if !databaseMic.connected {
                continue
            }
            if mic == databaseMic {
                return true
            } else if currentMic == databaseMic {
                return false
            }
        }
        return true
    }

    func markMicAsConnected(id: String) {
        database.mics.mics.first(where: { $0.id == id })?.connected = true
    }

    func markMicAsDisconnected(id: String) {
        database.mics.mics.first(where: { $0.id == id })?.connected = false
    }

    func updateMicsList() {
        let connectedMics = listMics()
        var databaseMics: [SettingsMicsMic] = []
        for mic in database.mics.mics {
            if mic.isExternal() {
                mic.connected = connectedMics.contains(where: { $0 == mic })
                databaseMics.append(mic)
            } else if let connectedMic = connectedMics.first(where: { $0 == mic }) {
                mic.connected = connectedMic.connected
                databaseMics.append(mic)
            }
        }
        for mic in connectedMics where !databaseMics.contains(mic) {
            databaseMics.insert(mic, at: 0)
        }
        database.mics.mics = databaseMics
    }

    private func getBuiltInMicOrientation(orientation: AVAudioSession.Orientation?) -> SettingsMic? {
        guard let orientation else {
            return nil
        }
        switch orientation {
        case .bottom:
            return .bottom
        case .front:
            return .front
        case .back:
            return .back
        case .top:
            return .top
        default:
            return nil
        }
    }

    func listMics() -> [SettingsMicsMic] {
        var mics: [SettingsMicsMic] = []
        listMediaPlayerMics(&mics)
        listSrtlaMics(&mics)
        listRtmpMics(&mics)
        listAudioSessionMics(&mics)
        return mics
    }

    private func listAudioSessionMics(_ mics: inout [SettingsMicsMic]) {
        for inputPort in AVAudioSession.sharedInstance().availableInputs ?? [] {
            if let dataSources = inputPort.dataSources, !dataSources.isEmpty {
                addAudioSessionBuiltinMics(&mics, inputPort, dataSources)
            } else {
                addAudioSessionExternalMics(&mics, inputPort)
            }
        }
    }

    private func addAudioSessionBuiltinMics(_ mics: inout [SettingsMicsMic],
                                            _ inputPort: AVAudioSessionPortDescription,
                                            _ dataSources: [AVAudioSessionDataSourceDescription])
    {
        for dataSource in dataSources {
            var name: String
            var builtInOrientation: SettingsMic?
            if inputPort.portType == .builtInMic {
                name = dataSource.dataSourceName
                builtInOrientation = getBuiltInMicOrientation(orientation: dataSource.orientation)
            } else {
                name = "\(inputPort.portName): \(dataSource.dataSourceName)"
            }
            let mic = SettingsMicsMic()
            mic.name = name
            mic.inputUid = inputPort.uid
            mic.dataSourceId = dataSource.dataSourceID.intValue
            mic.builtInOrientation = builtInOrientation
            mic.connected = true
            mics.append(mic)
        }
    }

    private func addAudioSessionExternalMics(
        _ mics: inout [SettingsMicsMic],
        _ inputPort: AVAudioSessionPortDescription
    ) {
        let mic = SettingsMicsMic()
        mic.name = inputPort.portName
        mic.inputUid = inputPort.uid
        mic.connected = true
        mics.append(mic)
    }

    private func listRtmpMics(_ mics: inout [SettingsMicsMic]) {
        for rtmpCamera in rtmpCameras() {
            guard let stream = getRtmpStream(camera: rtmpCamera) else {
                continue
            }
            let mic = SettingsMicsMic()
            mic.name = rtmpCamera
            mic.inputUid = stream.id.uuidString
            mic.connected = isRtmpStreamConnected(streamKey: stream.streamKey)
            mics.append(mic)
        }
    }

    private func listSrtlaMics(_ mics: inout [SettingsMicsMic]) {
        for srtlaCamera in srtlaCameras() {
            guard let stream = getSrtlaStream(camera: srtlaCamera) else {
                continue
            }
            let mic = SettingsMicsMic()
            mic.name = srtlaCamera
            mic.inputUid = stream.id.uuidString
            mic.connected = isSrtlaStreamConnected(streamId: stream.streamId)
            mics.append(mic)
        }
    }

    private func listMediaPlayerMics(_ mics: inout [SettingsMicsMic]) {
        for mediaPlayerCamera in mediaPlayerCameras() {
            guard let mediaPlayer = getMediaPlayer(camera: mediaPlayerCamera) else {
                continue
            }
            let mic = SettingsMicsMic()
            mic.name = mediaPlayerCamera
            mic.inputUid = mediaPlayer.id.uuidString
            mic.connected = true
            mics.append(mic)
        }
    }

    func selectMicById(id: String) {
        guard let mic = database.mics.mics.first(where: { $0.id == id }) else {
            // logger.info("xxx Mic with id \(id) not found")
            makeErrorToast(
                title: String(localized: "Mic not found"),
                subTitle: String(localized: "Mic id \(id)")
            )
            return
        }
        selectMic(mic: mic)
    }

    private func selectMic(mic: SettingsMicsMic) {
        if isRtmpMic(mic: mic) {
            selectMicRtmp(mic: mic)
        } else if isSrtlaMic(mic: mic) {
            selectMicSrtla(mic: mic)
        } else if isMediaPlayerMic(mic: mic) {
            selectMicMediaPlayer(mic: mic)
        } else {
            selectMicDefault(mic: mic)
        }
    }

    private func isRtmpMic(mic: SettingsMicsMic) -> Bool {
        guard let id = UUID(uuidString: mic.inputUid) else {
            return false
        }
        return getRtmpStream(id: id) != nil
    }

    private func isSrtlaMic(mic: SettingsMicsMic) -> Bool {
        guard let id = UUID(uuidString: mic.inputUid) else {
            return false
        }
        return getSrtlaStream(id: id) != nil
    }

    private func isMediaPlayerMic(mic: SettingsMicsMic) -> Bool {
        guard let id = UUID(uuidString: mic.inputUid) else {
            return false
        }
        return getMediaPlayer(id: id) != nil
    }

    private func selectMicRtmp(mic: SettingsMicsMic) {
        currentMic = mic
        database.mics.selectedId = mic.id
        let cameraId = getRtmpStream(camera: mic.name)?.id ?? .init()
        media.attachBufferedAudio(cameraId: cameraId)
        remoteControlStreamer?.stateChanged(state: RemoteControlState(mic: mic.id))
    }

    private func selectMicSrtla(mic: SettingsMicsMic) {
        currentMic = mic
        database.mics.selectedId = mic.id
        let cameraId = getSrtlaStream(camera: mic.name)?.id ?? .init()
        media.attachBufferedAudio(cameraId: cameraId)
        remoteControlStreamer?.stateChanged(state: RemoteControlState(mic: mic.id))
    }

    private func selectMicMediaPlayer(mic: SettingsMicsMic) {
        currentMic = mic
        database.mics.selectedId = mic.id
        let cameraId = getMediaPlayer(camera: mic.name)?.id ?? .init()
        media.attachBufferedAudio(cameraId: cameraId)
        remoteControlStreamer?.stateChanged(state: RemoteControlState(mic: mic.id))
    }

    private func selectMicDefault(mic: SettingsMicsMic) {
        // logger.info("xxx setting \(mic.name)")
        media.attachBufferedAudio(cameraId: nil)
        let preferStereoMic = database.debug.preferStereoMic
        netStreamLockQueue.async {
            let session = AVAudioSession.sharedInstance()
            for inputPort in session.availableInputs ?? [] {
                if mic.inputUid != inputPort.uid {
                    continue
                }
                try? session.setPreferredInput(inputPort)
                if let dataSourceID = mic.dataSourceId as? NSNumber {
                    for dataSource in inputPort.dataSources ?? [] {
                        if dataSourceID != dataSource.dataSourceID {
                            continue
                        }
                        try? self.setBuiltInMicAudioMode(dataSource: dataSource, preferStereoMic: preferStereoMic)
                        try? session.setInputDataSource(dataSource)
                    }
                }
            }
        }
        media.attachDefaultAudioDevice(builtinDelay: database.debug.builtinAudioAndVideoDelay)
        currentMic = mic
        database.mics.selectedId = mic.id
        remoteControlStreamer?.stateChanged(state: RemoteControlState(mic: mic.id))
    }

    private func setBuiltInMicAudioMode(dataSource: AVAudioSessionDataSourceDescription, preferStereoMic: Bool) throws {
        if preferStereoMic {
            if dataSource.supportedPolarPatterns?.contains(.stereo) == true {
                try dataSource.setPreferredPolarPattern(.stereo)
            } else {
                try dataSource.setPreferredPolarPattern(.none)
            }
        } else {
            try dataSource.setPreferredPolarPattern(.none)
        }
    }

    func keepSpeakerAlive(now: ContinuousClock.Instant) {
        guard keepSpeakerAliveLatestPlayed.duration(to: now) > .seconds(5 * 60) else {
            return
        }
        keepSpeakerAliveLatestPlayed = now
        guard let soundUrl = Bundle.main.url(forResource: "Alerts.bundle/Silence", withExtension: "mp3")
        else {
            return
        }
        keepSpeakerAlivePlayer = try? AVAudioPlayer(contentsOf: soundUrl)
        keepSpeakerAlivePlayer?.play()
    }

    func updateAudioLevel() {
        if database.show.audioLevel != audio.showing {
            audio.showing = database.show.audioLevel
        }
        let newAudioLevel = media.getAudioLevel()
        let newNumberOfAudioChannels = media.getNumberOfAudioChannels()
        if newNumberOfAudioChannels != audio.numberOfChannels {
            audio.numberOfChannels = newNumberOfAudioChannels
        }
        if newAudioLevel == audio.level {
            return
        }
        if abs(audio.level - newAudioLevel) > 5
            || newAudioLevel.isNaN
            || newAudioLevel == .infinity
            || audio.level.isNaN
            || audio.level == .infinity
        {
            audio.level = newAudioLevel
            if isWatchLocal() {
                sendAudioLevelToWatch(audioLevel: audio.level)
            }
        }
    }
}
