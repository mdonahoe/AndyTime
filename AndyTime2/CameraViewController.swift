import UIKit
import AVFoundation
import CommonCrypto
import LiveKit

// LiveKit credentials are loaded from the bundled `.env` file via Secrets.swift.
private let kDefaultRoom = "andytime"
private var kLiveKitURL:       String { Secrets.livekitURL }
private var kLiveKitAPIKey:    String { Secrets.livekitAPIKey }
private var kLiveKitAPISecret: String { Secrets.livekitAPISecret }

// MARK: - JWT helpers

private func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func livekitToken(apiKey: String, secret: String, identity: String, room: String) -> String {
    let header  = #"{"alg":"HS256","typ":"JWT"}"#
    let now     = Int(Date().timeIntervalSince1970)
    let payload = """
    {"iss":"\(apiKey)","sub":"\(identity)","iat":\(now),"exp":\(now + 21600),\
    "video":{"roomJoin":true,"room":"\(room)","canPublish":true,"canSubscribe":true,"canPublishData":true}}
    """
    let h = base64url(header.data(using: .utf8)!)
    let p = base64url(payload.data(using: .utf8)!)
    let message = "\(h).\(p)"
    let key = secret.data(using: .utf8)!
    let msg = message.data(using: .utf8)!
    var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    key.withUnsafeBytes { kp in
        msg.withUnsafeBytes { mp in
            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), kp.baseAddress, key.count, mp.baseAddress, msg.count, &hmac)
        }
    }
    return "\(message).\(base64url(Data(hmac)))"
}

// MARK: - Camera option

private struct CameraOption {
    let name: String
    let device: AVCaptureDevice
}

private func availableCameras() -> [CameraOption] {
    var opts: [CameraOption] = []
    func probe(_ type: AVCaptureDevice.DeviceType, _ pos: AVCaptureDevice.Position, _ name: String) {
        let s = AVCaptureDevice.DiscoverySession(deviceTypes: [type], mediaType: .video, position: pos)
        if let d = s.devices.first { opts.append(CameraOption(name: name, device: d)) }
    }
    probe(.builtInWideAngleCamera, .front, "Front")
    probe(.builtInWideAngleCamera, .back,  "Back Wide")
    probe(.builtInUltraWideCamera, .back,  "Back Ultra Wide")
    probe(.builtInTelephotoCamera, .back,  "Back Telephoto")
    return opts
}

// MARK: - Logging

private let kDevice = ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")

private func lkLog(_ msg: String, file: String = #file, line: Int = #line) {
    let fname = (file as NSString).lastPathComponent
    print("[LiveKit:\(kDevice)] \(msg)  (\(fname):\(line))")
}

// MARK: - CameraViewController

/// Publishes this device's camera + mic to LiveKit. Remote feeds live in RemoteCameraViewController.
class CameraViewController: UIViewController {

    private var room: Room { LiveKitManager.shared.room }
    private var cameraTrack: LocalVideoTrack?
    private var audioTrack: LocalAudioTrack?

    private var cameraOptions: [CameraOption] = []
    private var currentCameraIndex = 0

    private let videoView        = VideoView()
    private let placeholderLabel = UILabel()
    private let titleLabel       = UILabel()
    private let roomField        = UITextField()
    private let connectButton    = UIButton(type: .system)
    private let muteButton       = UIButton(type: .system)
    private let statsTextView    = UITextView()

    private var statsTimer: Timer?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        room.add(delegate: self)
        setupUI()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        statsTimer?.invalidate()
        statsTimer = nil
    }

    // MARK: - UI Setup

    private func setupUI() {
        titleLabel.text = "CAMERA"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        videoView.layoutMode = .fit
        videoView.mirrorMode = .auto
        videoView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)

        placeholderLabel.text = "Camera preview will appear here after connecting"
        placeholderLabel.textColor = UIColor(white: 0.4, alpha: 1)
        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.textAlignment = .center
        placeholderLabel.numberOfLines = 2
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholderLabel)

        roomField.text = kDefaultRoom
        roomField.borderStyle = .roundedRect
        roomField.autocapitalizationType = .none
        roomField.autocorrectionType = .no
        roomField.returnKeyType = .done
        roomField.delegate = self
        roomField.backgroundColor = UIColor(white: 0.15, alpha: 1)
        roomField.textColor = .white
        roomField.attributedPlaceholder = NSAttributedString(
            string: "Room name",
            attributes: [.foregroundColor: UIColor(white: 0.4, alpha: 1)]
        )
        roomField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(roomField)

        connectButton.setTitle("Connect", for: .normal)
        connectButton.backgroundColor = .systemBlue
        connectButton.setTitleColor(.white, for: .normal)
        connectButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        connectButton.layer.cornerRadius = 10
        connectButton.addTarget(self, action: #selector(toggleConnection), for: .touchUpInside)
        connectButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectButton)

        muteButton.setTitle("Mute", for: .normal)
        muteButton.backgroundColor = UIColor(white: 0.2, alpha: 1)
        muteButton.setTitleColor(.white, for: .normal)
        muteButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        muteButton.layer.cornerRadius = 10
        muteButton.isHidden = true
        muteButton.addTarget(self, action: #selector(toggleMute), for: .touchUpInside)
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(muteButton)

        statsTextView.isEditable = false
        statsTextView.isScrollEnabled = true
        statsTextView.backgroundColor = UIColor(white: 0.07, alpha: 1)
        statsTextView.textColor = .green
        statsTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statsTextView.layer.cornerRadius = 8
        statsTextView.text = "— not connected —"
        statsTextView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statsTextView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            videoView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.42),

            placeholderLabel.centerXAnchor.constraint(equalTo: videoView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: videoView.centerYAnchor),
            placeholderLabel.widthAnchor.constraint(equalTo: videoView.widthAnchor, constant: -40),

            roomField.topAnchor.constraint(equalTo: videoView.bottomAnchor, constant: 14),
            roomField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            roomField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            roomField.heightAnchor.constraint(equalToConstant: 40),

            connectButton.topAnchor.constraint(equalTo: roomField.bottomAnchor, constant: 12),
            connectButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            connectButton.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -6),
            connectButton.heightAnchor.constraint(equalToConstant: 44),

            muteButton.topAnchor.constraint(equalTo: connectButton.topAnchor),
            muteButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 6),
            muteButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            muteButton.heightAnchor.constraint(equalToConstant: 44),

            statsTextView.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 12),
            statsTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statsTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statsTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Connection

    /// Forces view load and connects without user interaction.
    func autoConnect() {
        _ = view
        guard room.connectionState == .disconnected else {
            lkLog("autoConnect skipped — already \(room.connectionState)")
            return
        }
        lkLog("autoConnect starting")
        Task { await connect() }
    }

    @objc private func toggleConnection() {
        switch room.connectionState {
        case .connected, .reconnecting:
            Task { await disconnect() }
        default:
            Task { await connect() }
        }
    }

    @objc private func toggleMute() {
        guard let audio = audioTrack else { return }
        Task {
            if audio.isMuted {
                try? await audio.unmute()
            } else {
                try? await audio.mute()
            }
            await MainActor.run {
                let muted = audio.isMuted
                muteButton.setTitle(muted ? "Unmute" : "Mute", for: .normal)
                muteButton.backgroundColor = muted ? .systemOrange : UIColor(white: 0.2, alpha: 1)
            }
            sendMuteState()
        }
    }

    private func connect() async {
        guard room.connectionState == .disconnected else { return }
        let roomName = roomField.text?.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? roomField.text!.trimmingCharacters(in: .whitespaces)
            : kDefaultRoom
        let identity = kDevice

        lkLog("connect() → room=\(roomName) identity=\(identity)")

        let token = livekitToken(
            apiKey: kLiveKitAPIKey,
            secret: kLiveKitAPISecret,
            identity: identity,
            room: roomName
        )

        await MainActor.run {
            connectButton.setTitle("Connecting…", for: .normal)
            connectButton.backgroundColor = .systemOrange
            connectButton.isEnabled = false
            view.endEditing(true)
        }

        appendStats("⟳ Connecting to room \"\(roomName)\"…")

        do {
            lkLog("room.connect starting")
            try await room.connect(url: kLiveKitURL, token: token)
            lkLog("room.connect succeeded — sid=\(room.sid?.description ?? "?")")
            appendStats("✓ Connected")

            lkLog("requesting camera permission")
            let videoGranted = await AVCaptureDevice.requestAccess(for: .video)
            lkLog("camera permission: \(videoGranted ? "granted" : "denied")")
            if videoGranted {
                cameraOptions = availableCameras()
                currentCameraIndex = 0
                lkLog("cameras available: \(cameraOptions.map(\.name))")
                let firstDevice = cameraOptions.first?.device
                let track = LocalVideoTrack.createCameraTrack(
                    name: "camera",
                    options: CameraCaptureOptions(device: firstDevice, dimensions: .h720_169, fps: 30)
                )
                self.cameraTrack = track
                lkLog("publishing video track")
                try await room.localParticipant.publish(videoTrack: track)
                lkLog("video track published")
                await MainActor.run {
                    videoView.track = track
                    placeholderLabel.isHidden = true
                }
                appendStats("✓ Camera published (\(cameraOptions.first?.name ?? "front"))")
                sendCameraList()
            } else {
                appendStats("✗ Camera permission denied")
            }

            // Microphone support is off for now: the mic is not published, and
            // mic permission is never requested. The session therefore stays on
            // `.playback` — see AudioSessionManager.
            //
            // `audioTrack` stays nil, which the mute plumbing already handles:
            // the Mute button stays hidden, and both `toggleMute()` and the
            // remote `setMute` message no-op. To re-enable, publish a
            // LocalAudioTrack here and give AudioSessionManager `.playAndRecord`
            // back.
            appendStats("• Mic disabled")

            startStatsTimer()

        } catch {
            lkLog("connect() error: \(error)")
            appendStats("✗ \(error.localizedDescription)")
            await MainActor.run {
                connectButton.setTitle("Connect", for: .normal)
                connectButton.backgroundColor = .systemBlue
                connectButton.isEnabled = true
            }
        }
    }

    private func disconnect() async {
        appendStats("⟳ Disconnecting…")
        stopStatsTimer()
        await room.disconnect()
    }

    // MARK: - Camera switching

    private func sendMuteState() {
        guard room.connectionState == .connected else { return }
        let muted = audioTrack?.isMuted ?? true
        let msg: [String: Any] = ["type": "muteState", "muted": muted]
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        Task {
            try? await room.localParticipant.publish(
                data: data,
                options: DataPublishOptions(topic: "camera-control", reliable: true)
            )
        }
    }

    private func sendCameraList() {
        guard room.connectionState == .connected, !cameraOptions.isEmpty else { return }
        let msg: [String: Any] = [
            "type":    "cameraList",
            "cameras": cameraOptions.map { $0.name },
            "current": currentCameraIndex,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        Task {
            try? await room.localParticipant.publish(
                data: data,
                options: DataPublishOptions(topic: "camera-control", reliable: true)
            )
        }
    }

    private func switchCamera(to index: Int) async {
        guard index >= 0, index < cameraOptions.count, index != currentCameraIndex else { return }
        guard let oldTrack = cameraTrack else { return }
        let option = cameraOptions[index]

        await MainActor.run { videoView.track = nil }

        if let pub = room.localParticipant.trackPublications.values
            .compactMap({ $0 as? LocalTrackPublication })
            .first(where: { $0.track === oldTrack }) {
            try? await room.localParticipant.unpublish(publication: pub)
        }

        let newTrack = LocalVideoTrack.createCameraTrack(
            name: "camera",
            options: CameraCaptureOptions(device: option.device, dimensions: .h720_169, fps: 30)
        )
        cameraTrack = newTrack
        currentCameraIndex = index
        do {
            try await room.localParticipant.publish(videoTrack: newTrack)
            await MainActor.run { videoView.track = newTrack }
            appendStats("📷 Camera: \(option.name)")
            sendCameraList()
        } catch {
            appendStats("✗ Camera switch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Stats

    private func startStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshStats()
        }
    }

    private func stopStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
    }

    private func refreshStats() {
        let state: String
        switch room.connectionState {
        case .connected:    state = "connected ✓"
        case .connecting:   state = "connecting…"
        case .reconnecting: state = "reconnecting…"
        default:            state = "disconnected"
        }

        let quality: String
        switch room.localParticipant.connectionQuality {
        case .excellent: quality = "excellent ◉"
        case .good:      quality = "good ◎"
        case .poor:      quality = "poor ○"
        default:         quality = "unknown"
        }

        let roomName     = room.name ?? "—"
        let roomSid      = room.sid?.description ?? "—"
        let localSid     = room.localParticipant.sid?.description ?? "—"
        let participants = room.remoteParticipants.count + 1
        let cameraState  = cameraTrack.map { $0.isMuted ? "muted" : "live ▶" } ?? "none"
        let micState     = audioTrack.map { $0.isMuted ? "muted 🔇" : "live ▶" } ?? "none"

        let text = """
        state:        \(state)
        room:         \(roomName)
        room sid:     \(roomSid)
        local sid:    \(localSid)
        participants: \(participants)
        quality:      \(quality)
        camera:       \(cameraState)
        mic:          \(micState)
        """

        DispatchQueue.main.async { [weak self] in
            self?.statsTextView.text = text
        }
    }

    private func appendStats(_ line: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let cur = statsTextView.text ?? ""
            let sep = (cur.isEmpty || cur == "— not connected —") ? "" : "\n"
            statsTextView.text = (cur == "— not connected —" ? "" : cur) + sep + line
            let range = NSRange(location: statsTextView.text.count - 1, length: 1)
            statsTextView.scrollRangeToVisible(range)
        }
    }
}

// MARK: - RoomDelegate

extension CameraViewController: RoomDelegate {

    func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldValue: ConnectionState) {
        lkLog("connectionState \(oldValue) → \(connectionState)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch connectionState {
            case .connected:
                connectButton.setTitle("Disconnect", for: .normal)
                connectButton.backgroundColor = .systemRed
                connectButton.isEnabled = true
            case .connecting:
                connectButton.setTitle("Connecting…", for: .normal)
                connectButton.backgroundColor = .systemOrange
                connectButton.isEnabled = false
            case .reconnecting:
                connectButton.setTitle("Reconnecting…", for: .normal)
                connectButton.backgroundColor = .systemOrange
                appendStats("⟳ Reconnecting…")
            default:
                connectButton.setTitle("Connect", for: .normal)
                connectButton.backgroundColor = .systemBlue
                connectButton.isEnabled = true
                placeholderLabel.isHidden = false
                muteButton.isHidden = true
                muteButton.setTitle("Mute", for: .normal)
                muteButton.backgroundColor = UIColor(white: 0.2, alpha: 1)
                stopStatsTimer()
                statsTextView.text = "— not connected —"
                cameraTrack = nil
                audioTrack = nil
            }
        }
    }

    func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        appendStats("✓ Track published: \(publication.source)")
    }

    func room(_ room: Room, didFailToConnectWithError error: LiveKitError?) {
        lkLog("didFailToConnect: \(error?.localizedDescription ?? "unknown")")
        appendStats("✗ Failed: \(error?.localizedDescription ?? "unknown error")")
    }

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        lkLog("participantDidConnect: \(participant.identity?.description ?? "?")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendCameraList()
            self?.sendMuteState()
        }
    }

    func room(_ room: Room, participant: RemoteParticipant?, didReceiveData data: Data, forTopic topic: String, encryptionType: EncryptionType) {
        guard topic == "camera-control",
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = msg["type"] as? String else { return }
        if type == "switchCamera", let index = msg["index"] as? Int {
            Task { await switchCamera(to: index) }
        } else if type == "setMute", let muted = msg["muted"] as? Bool {
            Task {
                if muted { try? await audioTrack?.mute() }
                else     { try? await audioTrack?.unmute() }
                await MainActor.run {
                    let isMuted = audioTrack?.isMuted ?? false
                    muteButton.setTitle(isMuted ? "Unmute" : "Mute", for: .normal)
                    muteButton.backgroundColor = isMuted ? .systemOrange : UIColor(white: 0.2, alpha: 1)
                }
                sendMuteState()
            }
        }
    }
}

// MARK: - UITextFieldDelegate

extension CameraViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
