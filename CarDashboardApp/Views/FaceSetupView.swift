import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import Vision

private func visionOrientation(_ uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch uiOrientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
}

enum FaceImageCropHelper {
    /// Recorta centrado en la primera cara (`VNDetectFaceRectanglesRequest`); si no hay, devuelve la imagen.
    static func croppedSquare(for image: UIImage, scale: CGFloat = 1.65) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let orientation = visionOrientation(image.imageOrientation)

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
            guard let face = request.results?.first else {
                return image
            }
            let w = CGFloat(cgImage.width)
            let h = CGFloat(cgImage.height)
            let bbox = face.boundingBox
            let faceW = bbox.width * w
            let faceH = bbox.height * h
            let cx = bbox.midX * w
            let cy = bbox.midY * h

            let side = min(w, h, max(faceW, faceH) * scale)
            var x = cx - side / 2
            var y = cy - side / 2
            x = max(0, min(x, w - side))
            y = max(0, min(y, h - side))
            let rect = CGRect(x: x, y: y, width: min(side, w - x), height: min(side, h - y)).integral
            guard let cropped = cgImage.cropping(to: rect) else { return image }
            return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
        } catch {
            return image
        }
    }

    /// Aplana orientación para evitar foto de cámara volteada.
    static func flattenOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let out = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return out
    }
}

/// Configura la foto de rostro opcional para avatares Gemini (solo local hasta generar).
struct FaceSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var profile: UserProfile?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraUIImage: UIImage?
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    avatarCircle

                    VStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(Color.black))
                        }
                        .buttonStyle(.plain)

                        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                            Label("Choose from library", systemImage: "photo")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Capsule().fill(Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)

                        if profile?.faceImageFilename != nil {
                            Button(role: .destructive) {
                                showingDeleteConfirm = true
                            } label: {
                                Text("Delete photo")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)

                    Divider().padding(.vertical, 4)

                    Toggle(
                        "Use my face when generating avatars",
                        isOn: Binding(
                            get: { profile?.useFaceByDefault ?? true },
                            set: {
                                profile?.useFaceByDefault = $0
                                try? modelContext.save()
                            }))
                    .disabled(profile?.faceImageFilename == nil)
                    .padding(.horizontal, 4)

                    HStack {
                        Text("Preferred gender")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Picker(
                            "",
                            selection: Binding(
                                get: {
                                    profile?.preferredGenderRaw ?? AvatarGender.female.rawValue
                                },
                                set: {
                                    profile?.preferredGenderRaw = $0
                                    try? modelContext.save()
                                })
                        ) {
                            Text("Female").tag(AvatarGender.female.rawValue)
                            Text("Male").tag(AvatarGender.male.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }
                    .padding(.horizontal, 4)

                    Text(
                        "Your photo is stored only on this device. It is only sent to the Gemini service when you generate an avatar; we do not share it with other users."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .multilineTextAlignment(.leading)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("My face")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.black)
                }
            }
            .onAppear {
                profile = UserProfile.current(in: modelContext)
            }
            .onChange(of: pickerItem) { _, item in
                Task { await loadPickerItem(item) }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: ingestCameraPick) {
                ClosetUIImagePickerBridge(image: $cameraUIImage)
                    .background(Color.black)
                    .ignoresSafeArea()
            }
            .confirmationDialog("Delete face photo?", isPresented: $showingDeleteConfirm, titleVisibility: .visible)
            {
                Button("Delete", role: .destructive) {
                    deleteFacePhoto()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemBackground))
                .frame(width: 200, height: 200)
            if let rel = profile?.faceImageFilename, let ui = ImageStore.load(rel) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(Color.black.opacity(0.22))
            }
        }
    }

    @MainActor
    private func loadPickerItem(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data)
        else { return }
        saveProcessedFace(img)
        pickerItem = nil
    }

    private func ingestCameraPick() {
        guard let raw = cameraUIImage else { return }
        cameraUIImage = nil
        saveProcessedFace(raw)
    }

    private func saveProcessedFace(_ image: UIImage) {
        guard let current = profile else {
            profile = UserProfile.current(in: modelContext)
            saveProcessedFace(image)
            return
        }

        var p = current
        let flat = FaceImageCropHelper.flattenOrientation(image)
        let cropped = FaceImageCropHelper.croppedSquare(for: flat, scale: 1.65)
        guard let jpeg = cropped.jpegData(compressionQuality: 0.9) else { return }

        if let old = p.faceImageFilename {
            ImageStore.deleteIfExists(old)
        }

        let rel = (try? ImageStore.save(jpeg, inFolder: "faces", filename: "me.jpg")) ?? ""
        guard !rel.isEmpty else { return }
        p.faceImageFilename = rel
        profile = p
        try? modelContext.save()
    }

    private func deleteFacePhoto() {
        guard let rel = profile?.faceImageFilename else { return }
        ImageStore.deleteIfExists(rel)
        profile?.faceImageFilename = nil
        try? modelContext.save()
    }
}
