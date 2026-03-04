import SwiftUI
import AVFoundation

struct BarcodeScannerView: UIViewControllerRepresentable {
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: BarcodeScannerView

        init(parent: BarcodeScannerView) {
            self.parent = parent
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !parent.didScan,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else {
                return
            }

            parent.didScan = true
            parent.onScan(value)
        }
    }

    let onScan: (String) -> Void
    var didScan: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        context.coordinator.parent = self
        uiViewController.setScanningEnabled(!didScan)
    }
}

final class ScannerViewController: UIViewController {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let statusLabel = UILabel()
    private var didConfigure = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        configureStatusLabel()
        configureSessionIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        statusLabel.frame = CGRect(x: 24, y: view.bounds.height - 120, width: view.bounds.width - 48, height: 48)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }

    func setScanningEnabled(_ isEnabled: Bool) {
        if isEnabled {
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.session.startRunning()
                }
            }
        } else if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }

    private func configureStatusLabel() {
        statusLabel.text = "Center the barcode in the frame"
        statusLabel.textAlignment = .center
        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusLabel.textColor = .white
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        statusLabel.layer.cornerRadius = 16
        statusLabel.layer.masksToBounds = true
        view.addSubview(statusLabel)
    }

    private func configureSessionIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        guard let device = AVCaptureDevice.default(for: .video) else {
            showStatus("Camera is not available on this device.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                showStatus("Could not start the camera.")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                showStatus("Could not read barcodes.")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(delegate, queue: .main)
            output.metadataObjectTypes = [
                .ean8, .ean13, .upce, .code128, .code39, .code93,
                .pdf417, .qr, .aztec, .dataMatrix, .itf14
            ]
        } catch {
            showStatus("Camera access failed.")
        }
    }

    private func showStatus(_ message: String) {
        statusLabel.text = message
    }
}
