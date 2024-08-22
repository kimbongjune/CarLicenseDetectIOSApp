import SwiftUI
import UIKit
import AVFoundation
import Photos

struct ScrollDetector: UIViewRepresentable {
    public init(
        onScroll: @escaping (CGFloat) -> Void,
        onDraggingEnd: @escaping (CGFloat, CGFloat) -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.onScroll = onScroll
        self.onDraggingEnd = onDraggingEnd
        self.onRefresh = onRefresh
    }

    /// ScrollView Delegate Methods
    public class Coordinator: NSObject, UIScrollViewDelegate {
        init(parent: ScrollDetector) {
            self.parent = parent
        }

        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.onScroll(scrollView.contentOffset.y)
        }

        public func scrollViewWillEndDragging(
            _: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            parent.onDraggingEnd(targetContentOffset.pointee.y, velocity.y)
        }

        public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView.panGestureRecognizer.view)
            parent.onDraggingEnd(scrollView.contentOffset.y, velocity.y)
        }

        @objc func handleRefresh() {
            parent.onRefresh()

            refreshControl?.endRefreshing()
        }

        var parent: ScrollDetector

        /// One time Delegate Initialization
        var isDelegateAdded: Bool = false
        var refreshControl: UIRefreshControl?
    }

    public var onScroll: (CGFloat) -> Void
    /// Offset, Velocity
    public var onDraggingEnd: (CGFloat, CGFloat) -> Void
    public var onRefresh: () -> Void

    public func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    public func makeUIView(context _: Context) -> UIView {
        return UIView()
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            /// Adding Delegate for only one time
            /// uiView - Background
            /// .superview = background {}
            /// .superview = VStack {}
            /// .superview = ScrollView {}
            if let scrollview = uiView.superview?.superview?.superview as? UIScrollView, !context.coordinator.isDelegateAdded {
                /// Adding Delegate
                scrollview.delegate = context.coordinator
                context.coordinator.isDelegateAdded = true

                /// Adding refresh control
                let refreshControl = UIRefreshControl()
                refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh), for: .valueChanged)
                scrollview.refreshControl = refreshControl
                context.coordinator.refreshControl = refreshControl
            }
        }
    }
}

struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var resultImage1: UIImage?
    @State private var resultImage2: UIImage?
    @State private var isShowingImagePicker = false
    @State private var isRefreshing = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var texts: String = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isShowingActionSheet = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 선택한 이미지 표시
                    if let selectedImage = selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                            .background(Color(UIColor.systemGray5))
                    } else {
                        Rectangle()
                            .fill(Color(UIColor.systemGray5))
                            .frame(height: 200)
                            .overlay(Text("차량 번호판을 선택해주세요")
                                        .foregroundColor(.gray))
                    }

                    // 사진 선택 버튼
                    Button(action: {
                            isShowingActionSheet = true
                        }) {
                            Text("사진 선택")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .actionSheet(isPresented: $isShowingActionSheet) {
                            ActionSheet(title: Text("사진 선택"), message: nil, buttons: [
                                .default(Text("카메라")) {
                                    checkPermissions(for: .camera) {
                                        isShowingImagePicker = true
                                        imagePickerSourceType = .camera
                                    }
                                },
                                .default(Text("갤러리")) {
                                    checkPermissions(for: .photoLibrary) {
                                        isShowingImagePicker = true
                                        imagePickerSourceType = .photoLibrary
                                    }
                                },
                                .cancel()
                            ])
                        }

                    // 번호판 인식 버튼
                    Button(action: {
                        uploadImage()
                    }) {
                        Text("번호판 인식")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }

                    // 프로그래스바 (애니메이션 예시)
                    if isRefreshing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }

                    // 서버 응답 이미지뷰 1
                    HStack(spacing: 16) {
                        if let resultImage1 = resultImage1 {
                            Image(uiImage: resultImage1)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 150)
                                .background(Color(UIColor.systemGray5))
                        }

                        if let resultImage2 = resultImage2 {
                            Image(uiImage: resultImage2)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 150)
                                .background(Color(UIColor.systemGray5))
                        }
                    }

                    // 서버 응답 텍스트
                    Text(texts)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(8)
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .background {
                         ScrollDetector(onScroll: { _ in }, onDraggingEnd: { _, _ in }, onRefresh: {
                             print("Refresh action")
                             refreshScreen()
                          })
                    }
            }
            .navigationTitle("번호판 인식")
            .sheet(isPresented: $isShowingImagePicker) {
                ImagePicker(sourceType: imagePickerSourceType, selectedImage: $selectedImage)
            }
            .alert(isPresented: $showErrorAlert) {
                Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
            }
            .onAppear {
                DispatchQueue.main.async {
                    requestPermissionsAtLaunch()
                }
            }
        }.navigationViewStyle(StackNavigationViewStyle())
    }

    // 앱 시작 시 권한 요청
    private func requestPermissionsAtLaunch() {
        checkPermissions(for: .camera) {
            print("카메라 권한 허용됨")
        }
        checkPermissions(for: .photoLibrary) {
            print("갤러리 권한 허용됨")
        }
    }

    private func refreshScreen() {
        // 데이터 초기화
        print("refreshScreen")
        selectedImage = nil
        resultImage1 = nil
        resultImage2 = nil
        texts = ""
        isRefreshing = false
    }

    private func uploadImage() {
        guard let selectedImage = selectedImage else {
            showError("사진을 먼저 선택해주세요")
            return
        }

        isRefreshing = true

        ApiService.shared.uploadImage(image: selectedImage) { result in
            DispatchQueue.main.async {
                self.isRefreshing = false
                switch result {
                case .success(let response):
                    if let base64Image = response.prediction, let imageData = Data(base64Encoded: base64Image) {
                        self.resultImage1 = UIImage(data: imageData)
                    }

                    // license_plate_image 표시
                    if let base64Image = response.licensePlateImage, let imageData = Data(base64Encoded: base64Image) {
                        self.resultImage2 = UIImage(data: imageData)
                    }

                    // 텍스트 출력
                    if let texts = response.texts {
                        self.texts = texts.joined(separator: "\n")
                    }
                case .failure(let error):
                    self.showError("API 요청 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }

    private func checkPermissions(for sourceType: UIImagePickerController.SourceType, completion: @escaping () -> Void) {
        switch sourceType {
        case .camera:
            let cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
            switch cameraAuthorizationStatus {
            case .authorized:
                completion()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted {
                        DispatchQueue.main.async {
                            completion()
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.showSettingsAlert(message: "카메라 접근 권한이 필요합니다. 설정으로 이동하여 권한을 허용해주세요.")
                        }
                    }
                }
            case .denied, .restricted:
                showSettingsAlert(message: "카메라 접근 권한이 필요합니다. 설정으로 이동하여 권한을 허용해주세요.")
            @unknown default:
                fatalError("Unknown camera authorization status")
            }

        case .photoLibrary:
            let photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus()
            switch photoAuthorizationStatus {
            case .authorized, .limited:
                completion()
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization { status in
                    if status == .authorized || status == .limited {
                        DispatchQueue.main.async {
                            completion()
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.showSettingsAlert(message: "갤러리 접근 권한이 필요합니다. 설정으로 이동하여 권한을 허용해주세요.")
                        }
                    }
                }
            case .denied, .restricted:
                showSettingsAlert(message: "갤러리 접근 권한이 필요합니다. 설정으로 이동하여 권한을 허용해주세요.")
            @unknown default:
                fatalError("Unknown photo library authorization status")
            }

        case .savedPhotosAlbum:
            checkPermissions(for: .photoLibrary, completion: completion)

        @unknown default:
            fatalError("Unknown source type")
        }
    }

    private func showSettingsAlert(message: String) {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        let alertController = UIAlertController(title: "권한 설정 필요", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "설정으로 이동", style: .default, handler: { _ in
            if UIApplication.shared.canOpenURL(settingsUrl) {
                UIApplication.shared.open(settingsUrl, options: [:], completionHandler: nil)
            }
        }))
        alertController.addAction(UIAlertAction(title: "취소", style: .cancel, handler: nil))

        // iOS 15 이상에서의 윈도우 처리
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alertController, animated: true, completion: nil)
        } else {
            // iOS 15 미만에서의 윈도우 처리
            if let rootViewController = UIApplication.shared.windows.first?.rootViewController {
                rootViewController.present(alertController, animated: true, completion: nil)
            }
        }
    }
}

// UIKit의 UIImagePickerController를 사용하는 SwiftUI 뷰
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
