import UIKit
import AVFoundation
import CommonCrypto
import LiveKit

// MARK: - Hardcoded LiveKit credentials (dev only)
private let kLiveKitURL       = "wss://andytime-n3a13lj5.livekit.cloud"
private let kLiveKitAPIKey    = "APITxc5HK2bwMX5"
private let kLiveKitAPISecret = "HplIUtx8sSCz2jo0rQulzY4GDoIx5QfcfjSunoNZlJk"
private let kDefaultRoom      = "andytime"

// MARK: - JWT helpers

private func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// Signs a LiveKit publisher access token using HMAC-SHA256.
private func livekitToken(apiKey: String, secret: String, identity: String, room: String) -> String {
    let header  = #"{"alg":"HS256","typ":"JWT"}"#
    let now     = Int(Date().timeIntervalSince1970)
    let payload = """
    {"iss":"\(apiKey)","sub":"\(identity)","iat":\(now),"exp":\(now + 21600),\
    "video":{"roomJoin":true,"room":"\(room)","canPublish":true,"canSubscribe":false,"canPublishData":true}}
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

// MARK: - CameraViewController

/// Streams the front camera via LiveKit WebRTC and shows live connection stats.
///
/// Swipe to this page after the video channels. Enter a room name and tap Connect —
/// a publisher token is generated automatically from the hardcoded API credentials.
/// Open viewer.html in a browser on the same network to receive the stream.
class CameraViewController: UIViewController {

    private let room = Room()
    private var cameraTrack: LocalVideoTrack?

    // UI
    private let titleLabel    = UILabel()
    private let videoView     = VideoView()
    private let placeholderLabel = UILabel()
    private let roomField     = UITextField()
    private let connectButton = UIButton(type: .system)
    private let statsTextView = UITextView()

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

        videoView.contentMode = .scaleAspectFit
        videoView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)

        placeholderLabel.text = "Camera preview will appear here after connecting"
        placeholderLabel.textColor = UIColor(white: 0.4, alpha: 1)
        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.textAlignment = .center
        placeholderLabel.numberOfLines = 2
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        videoView.addSubview(placeholderLabel)

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
        connectButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        connectButton.layer.cornerRadius = 10
        connectButton.addTarget(self, action: #selector(toggleConnection), for: .touchUpInside)
        connectButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectButton)

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
            connectButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            connectButton.widthAnchor.constraint(equalToConstant: 160),
            connectButton.heightAnchor.constraint(equalToConstant: 44),

            statsTextView.topAnchor.constraint(equalTo: connectButton.bottomAnchor, constant: 12),
            statsTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statsTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statsTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Connection

    @objc private func toggleConnection() {
        switch room.connectionState {
        case .connected, .reconnecting:
            Task { await disconnect() }
        default:
            Task { await connect() }
        }
    }

    private func connect() async {
        let roomName = roomField.text?.trimmingCharacters(in: .whitespaces).isEmpty == false
            ? roomField.text!.trimmingCharacters(in: .whitespaces)
            : kDefaultRoom

        let token = livekitToken(
            apiKey: kLiveKitAPIKey,
            secret: kLiveKitAPISecret,
            identity: "ios-camera",
            room: roomName
        )

        await MainActor.run {
            connectButton.setTitle("Connecting…", for: .normal)
            connectButton.backgroundColor = .systemOrange
            connectButton.isEnabled = false
            view.endEditing(true)
        }

        appendStats("⟳ Connecting to room "\(roomName)"…")

        do {
            try await room.connect(kLiveKitURL, token)
            appendStats("✓ Connected")

            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                appendStats("✗ Camera permission denied")
                return
            }

            let track = LocalVideoTrack.createCameraTrack(
                name: "camera",
                options: CameraCaptureOptions(
                    device: CameraCapturerUtils.device(position: .front),
                    dimensions: .h720_169,
                    fps: 30
                )
            )
            self.cameraTrack = track

            try await room.localParticipant.publish(videoTrack: track)
            appendStats("✓ Camera published")

            await MainActor.run {
                track.add(videoRenderer: videoView)
                placeholderLabel.isHidden = true
            }

            startStatsTimer()

        } catch {
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
        case .connected:   state = "connected ✓"
        case .connecting:  state = "connecting…"
        case .reconnecting:state = "reconnecting…"
        case .disconnected:state = "disconnected"
        }

        let quality: String
        switch room.localParticipant.connectionQuality {
        case .excellent: quality = "excellent ◉"
        case .good:      quality = "good ◎"
        case .poor:      quality = "poor ○"
        case .unknown:   quality = "unknown"
        @unknown default: quality = "?"
        }

        let roomName     = room.name ?? "—"
        let roomSid      = room.sid?.description ?? "—"
        let localSid     = room.localParticipant.sid.description
        let participants = room.remoteParticipants.count + 1
        let cameraState  = cameraTrack.map { $0.isMuted ? "muted" : "live ▶" } ?? "none"

        let text = """
        state:        \(state)
        room:         \(roomName)
        room sid:     \(roomSid)
        local sid:    \(localSid)
        participants: \(participants)
        quality:      \(quality)
        camera:       \(cameraState)
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
    func room(_ room: Room, didUpdate connectionState: ConnectionState, oldValue: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch connectionState {
            case .connected:
                connectButton.setTitle("Disconnect", for: .normal)
                connectButton.backgroundColor = .systemRed
                connectButton.isEnabled = true
            case .disconnected:
                connectButton.setTitle("Connect", for: .normal)
                connectButton.backgroundColor = .systemBlue
                connectButton.isEnabled = true
                placeholderLabel.isHidden = false
                stopStatsTimer()
                statsTextView.text = "— not connected —"
                cameraTrack = nil
            case .connecting:
                connectButton.setTitle("Connecting…", for: .normal)
                connectButton.backgroundColor = .systemOrange
                connectButton.isEnabled = false
            case .reconnecting:
                connectButton.setTitle("Reconnecting…", for: .normal)
                connectButton.backgroundColor = .systemOrange
                appendStats("⟳ Reconnecting…")
            }
        }
    }

    func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        appendStats("✓ Track published: \(publication.track?.kind.rawValue ?? "?")")
    }

    func room(_ room: Room, didFailToConnect error: Error) {
        appendStats("✗ Failed: \(error.localizedDescription)")
    }
}

// MARK: - UITextFieldDelegate

extension CameraViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
