/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The app's primary view controller that presents the camera interface.
*/

import UIKit
import AVFoundation
import CoreLocation
import Photos

class CameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
	
	let locationManager = CLLocationManager()
    
    private var progressIndicatorWidthConstraint: NSLayoutConstraint?
    private var flashIndicatorLeftConstraint: NSLayoutConstraint?
    
    // add an programmed eye position indicator
    private let eyePositionIndicator: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }()
    
    // Custom recording 2-sec--flash--4-sec button & countdown label
    private let takeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Take", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 5
        return button
    }()
    
    private let countdownLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 48, weight: .bold)
        label.isHidden = true
        return label
    }()
    
    private let progressBar: UIView = {
        let view = UIView()
        view.backgroundColor = .gray
        view.isHidden = true
        return view
    }()
    
    private let progressIndicator: UIView = {
        let view = UIView()
        view.backgroundColor = .green
        view.isHidden = true
        return view
    }()
    
    private let flashIndicator: UIView = {
        let view = UIView()
        view.backgroundColor = .yellow
        view.isHidden = true
        return view
    }()
    
    private let savedLabel: UILabel = {
        let label = UILabel()
        label.text = "Video Saved"
        label.textAlignment = .center
        label.textColor = .white
        label.isHidden = true
        return label
    }()
    
    // MARK: View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up the video preview view.
        previewView.session = session
		
		// Request location authorization so photos and videos can be tagged with their location.
		if locationManager.authorizationStatus == .notDetermined {
			locationManager.requestWhenInUseAuthorization()
		}
		
        checkVideoAuthorization()
        
        /*
         Setup the capture session.
         In general, it's not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Don't perform these tasks on the main queue because
         AVCaptureSession.startRunning() is a blocking call, which can
         take a long time. Dispatch session setup to the sessionQueue, so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }
        
        setupUI()
        
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateEyeIndicator()
        
        // Update flash indicator position
        let newLeftConstraintConstant = progressBar.bounds.width / 3
        if flashIndicatorLeftConstraint?.constant != newLeftConstraintConstant {
            flashIndicatorLeftConstraint?.constant = newLeftConstraintConstant
            view.layoutIfNeeded()
        }
    }
    
    private func checkVideoAuthorization() {
        // Check the video authorization status. Video access is required and
        // audio access is optional. If the user denies audio access, AVCam
        // won't record audio during movie recording.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera.
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. Suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateEyeIndicator()
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session if setup
                // succeeded.
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "AVCam doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                          options: [:],
                                                                                          completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    override var shouldAutorotate: Bool {
        // Disable autorotation of the interface when recording is in progress.
        if let movieFileOutput = movieFileOutput {
            return !movieFileOutput.isRecording
        }
        return true
    }
    
    // MARK: Session Management
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let session = AVCaptureSession()
    private var isSessionRunning = false
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue")
    
    private var setupResult: SessionSetupResult = .success
    
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    
    @IBOutlet private weak var previewView: PreviewView!
    
    // Call this on the session queue.
    /// - Tag: ConfigureSession
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        // Set up video input.
        do {
			// Handle the situation when the system-preferred camera is nil.
            var defaultVideoDevice: AVCaptureDevice?
            if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                defaultVideoDevice = frontCameraDevice
            }
            
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                        
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
                DispatchQueue.main.async {
                    // Dispatch video streaming to the main queue because
                    // AVCaptureVideoPreviewLayer is the backing layer for
                    // PreviewView. You can manipulate UIView only on the main
                    // thread. Note: As an exception to the above rule, it's not
                    // necessary to serialize video orientation changes on the
                    // AVCaptureVideoPreviewLayer’s connection with other
                    // session manipulation.
                    self.createDeviceRotationCoordinator()
                }
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add an audio input device.
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
            }
        } catch {
            print("Could not create audio device input: \(error)")
        }
        
        // Set up movie file output
        let movieFileOutput = AVCaptureMovieFileOutput()
        
        if session.canAddOutput(movieFileOutput) {
            session.addOutput(movieFileOutput)
            if let connection = movieFileOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
            self.movieFileOutput = movieFileOutput
        } else {
            print("Could not add movie file output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    @IBAction private func resumeInterruptedSession(_ resumeButton: UIButton) {
        sessionQueue.async {
            // The session might fail to start running, for example, if a phone
            // or FaceTime call is still using audio or video. This failure is
            // communicated by the session posting a runtime error notification.
            // To avoid repeatedly failing to start the session, only try to
            // restart the session in the error handler if you aren't trying to
            // resume the session.
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.resumeButton.isHidden = true
                }
            }
        }
    }

    // MARK: Device Configuration
        
    @IBOutlet private weak var cameraUnavailableLabel: UILabel!

    private var videoDeviceRotationCoordinator: AVCaptureDevice.RotationCoordinator!
    
    private var videoDeviceIsConnectedObservation: NSKeyValueObservation?
    
    private var videoRotationAngleForHorizonLevelPreviewObservation: NSKeyValueObservation?
    
    private func createDeviceRotationCoordinator() {
        videoDeviceRotationCoordinator = AVCaptureDevice.RotationCoordinator(device: videoDeviceInput.device, previewLayer: previewView.videoPreviewLayer)
        previewView.videoPreviewLayer.connection?.videoRotationAngle = videoDeviceRotationCoordinator.videoRotationAngleForHorizonLevelPreview
        
        videoRotationAngleForHorizonLevelPreviewObservation = videoDeviceRotationCoordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { _, change in
            guard let videoRotationAngleForHorizonLevelPreview = change.newValue else { return }
            
            self.previewView.videoPreviewLayer.connection?.videoRotationAngle = videoRotationAngleForHorizonLevelPreview
        }
    }
    
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
        
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                
                // Setting (focus/exposure)PointOfInterest alone does not
                // initiate a (focus/exposure) operation. Call
                // set(Focus/Exposure)Mode() to apply the new point of interest.
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
    // MARK: Recording Movies
    
    private var movieFileOutput: AVCaptureMovieFileOutput?
    
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
        
    @IBOutlet private weak var resumeButton: UIButton!
    
    var _supportedInterfaceOrientations: UIInterfaceOrientationMask = .all
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if movieFileOutput?.isRecording == true {
            return .all
        } else {
            return [.portrait, .landscapeLeft, .landscapeRight]
        }
    }
    
    /// - Tag: DidFinishRecording
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // Note: Because we use a unique file path for each recording, a new
        // recording won't overwrite a recording mid-save.
        func cleanup() {
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    print("Could not remove file at url: \(outputFileURL)")
                }
            }
            
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
                
                if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }
        
        var success = true
        
        if error != nil {
            print("Movie file finishing error: \(String(describing: error))")
            success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }
        
        if success {
            // Check the authorization status.
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Save the movie file to the photo library and cleanup.
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
						
						// Specify the movie's location.
						creationRequest.location = self.locationManager.location
                    }, completionHandler: { success, error in
                        if !success {
                            print("AVCam couldn't save the movie to your photo library: \(String(describing: error))")
                        }
                        cleanup()
                    })
                } else {
                    cleanup()
                }
            }
        } else {
            cleanup()
        }
        
        // Enable the Camera and Record buttons to let the user switch camera
        // and start another recording.
        DispatchQueue.main.async {
            self.progressBar.isHidden = true
            self.progressIndicator.isHidden = true
            self.flashIndicator.isHidden = true
            self.savedLabel.isHidden = false
            // Only enable the ability to change camera if the device has more than one camera.
            // After the recording finishes, allow rotation to continue.
            self.setNeedsUpdateOfSupportedInterfaceOrientations()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.savedLabel.isHidden = true
                self.takeButton.isEnabled = true
                self.takeButton.isHidden = false
            }
        }
    }

    
    // MARK: KVO and Notifications
    
    private var keyValueObservations = [NSKeyValueObservation]()
    /// - Tag: ObserveInterruption
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }
            
            DispatchQueue.main.async {
                // Only enable the ability to change camera if the device has more than one camera.
                self.takeButton.isEnabled = isSessionRunning
            }
        }
        keyValueObservations.append(keyValueObservation)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionRuntimeError),
                                               name: .AVCaptureSessionRuntimeError,
                                               object: session)
        
        // A session can only run when the app is full screen. It will be
        // interrupted in a multi-app layout, introduced in iOS 9, see also the
        // documentation of AVCaptureSessionInterruptionReason. Add observers to
        // handle these session interruptions and show a preview is paused
        // message. See `AVCaptureSessionWasInterruptedNotification` for other
        // interruption reasons.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted),
                                               name: .AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded),
                                               name: .AVCaptureSessionInterruptionEnded,
                                               object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
    
    private var systemPreferredCameraContext = 0
    
    private func setupUI() {
        setupEyePositionIndicator()
        setupTakeButton()
        setupCountdownLabel()
        setupProgressBar()
    }
    
    // set up the progress bar
    private func setupProgressBar() {
        view.addSubview(progressBar)
        progressBar.addSubview(progressIndicator)
        progressBar.addSubview(flashIndicator)
        view.addSubview(savedLabel)
        
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        flashIndicator.translatesAutoresizingMaskIntoConstraints = false
        savedLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let progressIndicatorWidthConstraint = progressIndicator.widthAnchor.constraint(equalTo: progressBar.widthAnchor, multiplier: 0)
        let flashIndicatorLeftConstraint = flashIndicator.leftAnchor.constraint(equalTo: progressBar.leftAnchor)
        
        NSLayoutConstraint.activate([
            progressBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            progressBar.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            progressBar.heightAnchor.constraint(equalToConstant: 4),
            
            progressIndicator.leftAnchor.constraint(equalTo: progressBar.leftAnchor),
            progressIndicator.topAnchor.constraint(equalTo: progressBar.topAnchor),
            progressIndicator.bottomAnchor.constraint(equalTo: progressBar.bottomAnchor),
            progressIndicatorWidthConstraint,
            
            flashIndicatorLeftConstraint,
            flashIndicator.topAnchor.constraint(equalTo: progressBar.topAnchor),
            flashIndicator.bottomAnchor.constraint(equalTo: progressBar.bottomAnchor),
            flashIndicator.widthAnchor.constraint(equalToConstant: 4),
            
            savedLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            savedLabel.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor)
        ])
        
        self.flashIndicatorLeftConstraint = flashIndicatorLeftConstraint
        self.progressIndicatorWidthConstraint = progressIndicatorWidthConstraint
    }
    
    // setup the eye position indicator
    private func setupEyePositionIndicator() {
        view.addSubview(eyePositionIndicator)
        eyePositionIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            eyePositionIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            eyePositionIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            eyePositionIndicator.widthAnchor.constraint(equalTo: view.widthAnchor),
            eyePositionIndicator.heightAnchor.constraint(equalTo: view.heightAnchor)
        ])
        
        updateEyeIndicator()
    }
    
    private func updateEyeIndicator() {
        eyePositionIndicator.layer.sublayers?.forEach { $0.removeFromSuperlayer()}
        
        let isLandscape: Bool
        if let windowScene = view.window?.windowScene {
            isLandscape = windowScene.interfaceOrientation.isLandscape
        } else {
            isLandscape = UIDevice.current.orientation.isLandscape
        }
        let sizeFactor: CGFloat = isLandscape ? 1.5 : 1.0
        
        let ovalWidth: CGFloat = 160 * sizeFactor
        let ovalHeight: CGFloat = 100 * sizeFactor
        let noseSpacing: CGFloat = 40 * sizeFactor
        
        let totalWidth = (ovalWidth * 2) + noseSpacing
        let xOffset = (eyePositionIndicator.bounds.width - totalWidth) / 2
        let yOffset = (eyePositionIndicator.bounds.height - ovalHeight) / 2
        
        let leftEyeOval = CAShapeLayer()
        let rightEyeOval = CAShapeLayer()
        
        let leftOvalPath = UIBezierPath(ovalIn: CGRect(x: xOffset, y: yOffset, width: ovalWidth, height: ovalHeight))
        let rightOvalPath = UIBezierPath(ovalIn: CGRect(x: xOffset + ovalWidth + noseSpacing, y: yOffset, width: ovalWidth, height: ovalHeight))
        
        leftEyeOval.path = leftOvalPath.cgPath
        rightEyeOval.path = rightOvalPath.cgPath
        
        leftEyeOval.strokeColor = UIColor.white.cgColor
        rightEyeOval.strokeColor = UIColor.white.cgColor
        
        leftEyeOval.fillColor = UIColor.clear.cgColor
        rightEyeOval.fillColor = UIColor.clear.cgColor
        
        leftEyeOval.lineWidth = 2
        rightEyeOval.lineWidth = 2
        
        eyePositionIndicator.layer.addSublayer(leftEyeOval)
        eyePositionIndicator.layer.addSublayer(rightEyeOval)
    }
    
    // add custom record button & countdown setup
    private func setupTakeButton() {
        view.addSubview(takeButton)
        takeButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            takeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            takeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            takeButton.widthAnchor.constraint(equalToConstant: 100),
            takeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        takeButton.addTarget(self, action: #selector(takeButtonTapped), for: .touchUpInside)
    }
    
    private func setupCountdownLabel() {
        view.addSubview(countdownLabel)
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            countdownLabel.widthAnchor.constraint(equalToConstant: 100),
            countdownLabel.heightAnchor.constraint(equalToConstant: 100)
        ])
    }
    
    @objc private func takeButtonTapped() {
        takeButton.isHidden = true
        countdownLabel.isHidden = false
        countdownLabel.center = takeButton.center
        ensureMovieRecordingSetup()
        startCountdown()
    }
    
    private func ensureMovieRecordingSetup() {
        sessionQueue.async {
            if self.movieFileOutput == nil {
                let movieFileOutput = AVCaptureMovieFileOutput()
                if self.session.canAddOutput(movieFileOutput) {
                    self.session.beginConfiguration()
                    self.session.addOutput(movieFileOutput)
                    self.session.sessionPreset = .high
                    self.session.commitConfiguration()
                    self.movieFileOutput = movieFileOutput
                }
            }
        }
    }
    
    private func startCountdown() {
        resetProgressBar()
        var countdown = 3
        countdownLabel.isHidden = false
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return}
            self.countdownLabel.text = "\(countdown)"
            countdown -= 1
            
            if countdown < 0 {
                timer.invalidate()
                self.countdownLabel.isHidden = true
                self.progressBar.isHidden = false
                self.progressIndicator.isHidden = false
                self.flashIndicator.isHidden = false
                
                let newLeftConstraintConstant = self.progressBar.bounds.width / 3
                self.flashIndicatorLeftConstraint?.constant = newLeftConstraintConstant
                
                self.startRecording()
                self.animateProgressBar()
            }
        }
    }
    
    private func startRecording() {
        guard let movieFileOutput = self.movieFileOutput else {
            print("Movie file output is not available")
            return
        }
        
        // Disable buttons
        DispatchQueue.main.async {
            self.takeButton.isEnabled = false
        }
        
        let videoRotationAngle = self.videoDeviceRotationCoordinator.videoRotationAngleForHorizonLevelCapture
        
        sessionQueue.async {
            if !movieFileOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                // Update the orientation on the movie file output video connection before recording.
                let movieFileOutputConnection = movieFileOutput.connection(with: .video)
                movieFileOutputConnection?.videoRotationAngle = videoRotationAngle
                
                let availableVideoCodecTypes = movieFileOutput.availableVideoCodecTypes
                
                if availableVideoCodecTypes.contains(.hevc) {
                    movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
                }
                
                // Start recording to a temporary file.
                let outputFileName = NSUUID().uuidString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
                
                // Schedule flash activation
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.toggleFlash(on: true)
                }
                
                // Schedule recording stop
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.2) {
                    self.stopRecording()
                }
                
                // Update UI for orientation changes
                DispatchQueue.main.async {
                    self.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
    }
    
    private func toggleFlash(on: Bool) {
        sessionQueue.async {
            guard let device = self.videoDeviceInput?.device else { return }
            
            if device.hasTorch {
                do {
                    try device.lockForConfiguration()
                    if device.isTorchModeSupported(on ? .on : .off) {
                        device.torchMode = on ? .on : .off
                    }
                    device.unlockForConfiguration()
                    
                    if on {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.toggleFlash(on: false)
                        }
                    }
                } catch {
                    print("Error setting torch: \(error)")
                }
            }
        }
        
        if on {
            DispatchQueue.main.async {
                let flashView = UIView(frame: self.previewView.bounds)
                flashView.backgroundColor = .white
                flashView.alpha = 0
                self.previewView.addSubview(flashView)
                
                UIView.animate(withDuration: 0.1, animations: {
                    flashView.alpha = 1
                }) { _ in
                    UIView.animate(withDuration: 0.1, delay: 0.2, animations: {
                        flashView.alpha = 0
                    }) { _ in
                        flashView.removeFromSuperview()
                    }
                }
            }
        }
    }
    
    private func stopRecording() {
        sessionQueue.async {
            if self.movieFileOutput?.isRecording == true {
                self.movieFileOutput?.stopRecording()
            }
        }
    }
    
    private func animateProgressBar() {
        UIView.animate(withDuration: 6.2, delay: 0, options: .curveLinear) {
            //self.progressIndicator.frame.size.width = self.progressBar.frame.width
            self.progressIndicatorWidthConstraint?.constant = self.progressBar.bounds.width
            self.view.layoutIfNeeded()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            UIView.animate(withDuration: 0.2) {
                self.flashIndicator.backgroundColor = .white
            } completion: {_ in
                UIView.animate(withDuration: 0.2) {
                    self.flashIndicator.backgroundColor = .yellow
                }
            }
        }
    }
    
    private func resetProgressBar() {
        progressIndicatorWidthConstraint?.constant = 0
        view.layoutIfNeeded()
    }
    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    /// - Tag: HandleRuntimeError
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        
        print("Capture session runtime error: \(error)")
        // If media services were reset, and the last start succeeded, restart
        // the session.
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            resumeButton.isHidden = false
        }
    }
    
    /// - Tag: HandleInterruption
    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        // In some scenarios you want to enable the user to resume the session.
        // For example, if music playback is initiated from Control Center while
        // using AVCam, then the user can let AVCam resume the session running,
        // which will stop music playback. Note that stopping music playback in
        // Control Center will not automatically resume the session. Also note
        // that it's not always possible to resume, see
        // `resumeInterruptedSession(_:)`.
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
            
            var showResumeButton = false
            if reason == .audioDeviceInUseByAnotherClient || reason == .videoDeviceInUseByAnotherClient {
                showResumeButton = true
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                // Fade-in a label to inform the user that the camera is
                // unavailable.
                cameraUnavailableLabel.alpha = 0
                cameraUnavailableLabel.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    self.cameraUnavailableLabel.alpha = 1
                }
            } else if reason == .videoDeviceNotAvailableDueToSystemPressure {
                print("Session stopped running due to shutdown system pressure level.")
            }
            if showResumeButton {
                // Fade-in a button to enable the user to try to resume the
                // session running.
                resumeButton.alpha = 0
                resumeButton.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    self.resumeButton.alpha = 1
                }
            }
        }
    }
    
    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
        
        if !resumeButton.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.resumeButton.alpha = 0
            }, completion: { _ in
                self.resumeButton.isHidden = true
            })
        }
        if !cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.cameraUnavailableLabel.alpha = 0
            }, completion: { _ in
                self.cameraUnavailableLabel.isHidden = true
            }
            )
        }
    }
    
    @objc private func orientationChanged() {
        updateEyeIndicator()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
    }
}
