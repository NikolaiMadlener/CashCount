//
//  CameraView.swift
//  CashCount
//
//  Created by Nikolai Madlener on 19.07.21.
//

import SwiftUI
import AVFoundation
import CoreML
import Vision

struct CameraView: View {
    
    @StateObject var cameraVM = CameraViewModel()
    
    var body: some View {
        ZStack {
            CameraPreview(camera: cameraVM).edgesIgnoringSafeArea(.top)
            VStack {
                if cameraVM.isTaken {
                    HStack {
                        Spacer()
                        Button(action: {cameraVM.reTake()}, label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera").foregroundColor(.black)
                                .padding()
                                .background(Color.white)
                                .clipShape(Circle())
                        }).padding(.trailing, 10)
                    }
                }
                Spacer()
                HStack {
                    if cameraVM.isTaken {
                        if !cameraVM.isCounted {
                            Button(action: {cameraVM.countCash()}, label: {
                                Text("Count")
                                    .foregroundColor(.black)
                                    .fontWeight(.semibold)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 20)
                                    .background(Color.white)
                                    .clipShape(Capsule())
                            })
                            .padding(.leading)
                        } else {
                            //                            Text(String(format: "%.2f", cameraVM.cash) + "€")
                            Text(cameraVM.classificationLabel)
                                .foregroundColor(.black)
                                .fontWeight(.semibold)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 20)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }
                    } else {
                        Button(action: {cameraVM.takePic()}, label: {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 60, height: 60)
                                
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: 70, height: 70)
                            }
                        })
                    }
                }.frame(height: 70)
            }
        }.onAppear(perform: {
            cameraVM.check()
            
        })
    }
}

class CameraViewModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    
    @Published var classificationLabel: String = ""
    
    @Published var isTaken = false
    @Published var isCounted = false
    @Published var alert = false
    
    @Published var session = AVCaptureSession()
    @Published var output = AVCapturePhotoOutput()
    
    @Published var preview : AVCaptureVideoPreviewLayer!
    
    @Published var isSaved = false
    @Published var picData = Data(count: 0)
    
    @Published var cash = 0.0
    
    func check() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized :
            setUp()
            return
        case .notDetermined :
            AVCaptureDevice.requestAccess(for: .video) { (status) in
                if status {
                    self.setUp()
                }
            }
        case .denied :
            self.alert.toggle()
            return
        default:
            return
        }
    }
    
    func setUp() {
        do {
            self.session.beginConfiguration()
            
            let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
            
            let input = try AVCaptureDeviceInput(device: device!)
            
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }
            
            self.session.commitConfiguration()
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func takePic() {
        self.output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        DispatchQueue.global(qos: .background).async {
            self.session.stopRunning()
            
            DispatchQueue.main.async {
                withAnimation{self.isTaken.toggle()}
            }
        }
    }
    
    func reTake() {
        
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
            
            DispatchQueue.main.async {
                withAnimation{self.isTaken.toggle()}
                self.isSaved = false
                self.isCounted = false
                self.picData = Data(count: 0)
            }
        }
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if error != nil {
            return
        }
        print ("pic taken...")
        guard let imageData = photo.fileDataRepresentation() else {
            return
        }
        self.picData = imageData
        countCash()
        
    }
    
    func countCash() {
        self.isCounted = true
        updateDetections()
    }
    
    lazy var detectionRequest: VNCoreMLRequest = {
            do {
                let model = try VNCoreMLModel(for: YOLOv3FP16().model)
                
                let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                    self?.processDetections(for: request, error: error)
                })
                request.imageCropAndScaleOption = .scaleFit
                return request
            } catch {
                fatalError("Failed to load Vision ML model: \(error)")
            }
        }()
    
    private func updateDetections() {
        guard let image = UIImage(data: self.picData) else {
            print("no image")
            return
        }
        image.resizeImageTo(size: CGSize(width: 416, height: 416))
        let orientation = CGImagePropertyOrientation(rawValue: UInt32(image.imageOrientation.rawValue))
        guard let ciImage = CIImage(image: image) else { fatalError("Unable to create \(CIImage.self) from \(image).") }
        
        DispatchQueue.global(qos: .background).async {
            let handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation!)
            do {
                try handler.perform([self.detectionRequest])
            } catch {
                print("Failed to perform detection.\n\(error.localizedDescription)")
            }
        }
    }
    
    private func processDetections(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            guard let results = request.results else {
                print("Unable to detect anything.\n\(error!.localizedDescription)")
                return
            }
            
            let detections = results as! [VNRecognizedObjectObservation]
            self.drawDetectionsOnPreview(detections: detections)
        }
    }
    
    func drawDetectionsOnPreview(detections: [VNRecognizedObjectObservation]) {
        guard let image = UIImage(data: self.picData) else {
            return
        }
        
        let imageSize = image.size
        let scale: CGFloat = 0
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        
        image.draw(at: CGPoint.zero)
        
        for detection in detections {
            
            print(detection.labels.map({"\($0.identifier) confidence: \($0.confidence)"}).joined(separator: "\n"))
            print("------------")
            
            //            The coordinates are normalized to the dimensions of the processed image, with the origin at the image's lower-left corner.
            let boundingBox = detection.boundingBox
            let rectangle = CGRect(x: boundingBox.minX*image.size.width, y: (1-boundingBox.minY-boundingBox.height)*image.size.height, width: boundingBox.width*image.size.width, height: boundingBox.height*image.size.height)
            UIColor(red: 0, green: 1, blue: 0, alpha: 0.4).setFill()
            UIRectFillUsingBlendMode(rectangle, CGBlendMode.normal)
        }
        
        self.classificationLabel = detections.first?.labels.map({"\($0.identifier)"}).first ?? ""
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        self.picData = newImage?.cgImage?.dataProvider?.data as Data? ?? Data(count: 0)
        self.preview = AVCaptureVideoPreviewLayer(layer: newImage)
        print("new picData")
    }
}
    
    
    struct CameraView_Previews: PreviewProvider {
        static var previews: some View {
            CameraView()
        }
    }
