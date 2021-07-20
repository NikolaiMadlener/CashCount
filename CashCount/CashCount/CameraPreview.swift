//
//  CameraPreview.swift
//  CashCount
//
//  Created by Nikolai Madlener on 19.07.21.
//

import UIKit
import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var camera: CameraViewModel
    
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(frame: UIScreen.main.bounds)
        camera.preview = AVCaptureVideoPreviewLayer(session: camera.session)
        camera.preview.frame = view.frame
        
        camera.preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(camera.preview)
        
        camera.session.startRunning()
        
        return view
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        print("update")
        
//        uiView.image = UIImage(data: camera.picData)
    }
}
