import AVFoundation
import LiveKit
import UIKit

/// A view backed by an `AVCaptureVideoPreviewLayer`, for the own-capture path.
private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// A plain "see yourself" page — a live front camera preview.
///
/// Unlike `CameraViewController` this page stays available while the device is
/// locked into the app, and it has no controls: it is just a mirror.
///
/// It does not depend on LiveKit being connected, but it does have to cooperate
/// with it. iOS only lets one `AVCaptureSession` hold a given camera at a time,
/// and `CameraViewController` is usually already capturing the front camera to
/// publish it. Opening a second session on the same device would interrupt that
/// one, so:
///
/// - when LiveKit is publishing a camera track, this renders that same track
/// - otherwise it runs its own capture session
///
/// It swaps between the two as tracks come and go, and only holds the camera
/// while the page is actually on screen.
class MirrorViewController: UIViewController {

    private let liveKitVideoView = VideoView()
    private let previewView = CameraPreviewView()
    private let statusLabel = UILabel()

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.mdonahoe.AndyTime2.mirror-session")
    private var isCaptureSessionConfigured = false
    private var isVisible = false

    // MARK: - Lifecycle

    init() {
        super.init(nibName: nil, bundle: nil)
        LiveKitManager.shared.room.add(delegate: self)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        LiveKitManager.shared.room.remove(delegate: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        // Safety net for the narrow window where LiveKit starts capturing while
        // our own session is already running — whoever loses the device gets
        // these, so yield rather than sit on a dead preview.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureInterruption(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureInterruptionEnded),
            name: AVCaptureSession.interruptionEndedNotification,
            object: captureSession
        )
    }

    @objc private func handleCaptureInterruption(_ notification: Notification) {
        let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int)
            .flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
        // Backgrounding and system-pressure interruptions resolve themselves;
        // only yield when something else has actually taken the camera.
        guard reason == .videoDeviceInUseByAnotherClient else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, isVisible else { return }
            if publishedCameraTrack != nil {
                selectSource()
            } else {
                // Don't immediately retry — that just fights for the device.
                stopOwnCapture()
                setStatus("Camera is in use")
            }
        }
    }

    @objc private func handleCaptureInterruptionEnded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, isVisible else { return }
            selectSource()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        selectSource()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isVisible = false
        // Don't sit on the camera (or on a renderer) while off screen.
        stopOwnCapture()
        liveKitVideoView.track = nil
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updatePreviewRotation()
        }, completion: nil)
    }

    private func setupUI() {
        view.backgroundColor = .black

        for subview in [previewView, liveKitVideoView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: view.topAnchor),
                subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        previewView.previewLayer.session = captureSession
        previewView.previewLayer.videoGravity = .resizeAspectFill
        // The preview layer mirrors a front camera by default, which is what a
        // mirror should do, so `automaticallyAdjustsVideoMirroring` is left alone.

        liveKitVideoView.layoutMode = .fill
        liveKitVideoView.mirrorMode = .auto
        liveKitVideoView.backgroundColor = .black

        statusLabel.textColor = UIColor(white: 0.5, alpha: 1)
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40),
        ])
    }

    // MARK: - Source selection

    /// The camera track LiveKit is already publishing, if any.
    private var publishedCameraTrack: VideoTrack? {
        LiveKitManager.shared.room.localParticipant.firstCameraVideoTrack
    }

    /// Picks whichever source is available without taking the camera away from
    /// LiveKit. Safe to call repeatedly.
    private func selectSource() {
        guard isVisible, isViewLoaded else { return }

        if let track = publishedCameraTrack {
            stopOwnCapture()
            previewView.isHidden = true
            liveKitVideoView.isHidden = false
            liveKitVideoView.track = track
            setStatus(nil)
        } else {
            liveKitVideoView.track = nil
            liveKitVideoView.isHidden = true
            previewView.isHidden = false
            startOwnCapture()
        }
    }

    private func setStatus(_ text: String?) {
        statusLabel.text = text
        statusLabel.isHidden = (text == nil)
    }

    // MARK: - Own capture session

    private func startOwnCapture() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        // Re-check the source: LiveKit may have published while we asked.
                        selectSource()
                    } else {
                        setStatus("Camera access is off")
                    }
                }
            }
        default:
            setStatus("Camera access is off")
        }
    }

    private func configureAndStartCapture() {
        setStatus(nil)
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !isCaptureSessionConfigured {
                captureSession.beginConfiguration()
                // This session is video only — it must never touch the audio
                // session, which AudioSessionManager owns.
                captureSession.automaticallyConfiguresApplicationAudioSession = false
                captureSession.sessionPreset = .high

                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                   let input = try? AVCaptureDeviceInput(device: device),
                   captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                    isCaptureSessionConfigured = true
                }
                captureSession.commitConfiguration()
            }

            guard isCaptureSessionConfigured else {
                DispatchQueue.main.async { [weak self] in
                    self?.setStatus("No front camera available")
                }
                return
            }

            // The preview layer already holds the session; no output is needed.
            if !captureSession.isRunning {
                captureSession.startRunning()
            }

            DispatchQueue.main.async { [weak self] in
                self?.updatePreviewRotation()
            }
        }
    }

    private func stopOwnCapture() {
        sessionQueue.async { [weak self] in
            guard let self, captureSession.isRunning else { return }
            captureSession.stopRunning()
        }
    }

    private func updatePreviewRotation() {
        guard let connection = previewView.previewLayer.connection else { return }
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait

        if #available(iOS 17.0, *) {
            // 0° is the camera's native orientation, which lines up with
            // landscapeRight; the rest follow counterclockwise.
            let angle: CGFloat
            switch orientation {
            case .portrait:           angle = 90
            case .portraitUpsideDown: angle = 270
            case .landscapeLeft:      angle = 180
            case .landscapeRight:     angle = 0
            default:                  angle = 90
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else {
            let videoOrientation: AVCaptureVideoOrientation
            switch orientation {
            case .portraitUpsideDown: videoOrientation = .portraitUpsideDown
            case .landscapeLeft:      videoOrientation = .landscapeLeft
            case .landscapeRight:     videoOrientation = .landscapeRight
            default:                  videoOrientation = .portrait
            }
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = videoOrientation
            }
        }
    }
}

// MARK: - RoomDelegate

extension MirrorViewController: RoomDelegate {

    /// LiveKit just took the camera — switch to rendering its track instead of
    /// competing for the device. Also covers CameraViewController's camera switch,
    /// which republishes a new track.
    func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        guard publication.source == .camera else { return }
        DispatchQueue.main.async { [weak self] in
            self?.selectSource()
        }
    }

    /// LiveKit gave the camera back — fall back to our own capture session.
    func room(_ room: Room, participant: LocalParticipant, didUnpublishTrack publication: LocalTrackPublication) {
        guard publication.source == .camera else { return }
        DispatchQueue.main.async { [weak self] in
            self?.selectSource()
        }
    }
}
