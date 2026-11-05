import DesignSystem
import ImageIO
import Library
import PhotosUI
import SwiftUI
import UIKit

extension View {
    /// Photo picker for a playlist or collection cover. Set `itemID` to present it; the chosen
    /// photo is cropped square, resized and uploaded as the item's server image, which then takes
    /// the place of its generated cover.
    func coverImagePicker(itemID: Binding<String?>, owner: LibraryEditor.CoverOwner) -> some View {
        modifier(CoverImagePicker(itemID: itemID, owner: owner))
    }
}

/// A playlist or collection's cover items, shared by its page menu and its long-press menu:
/// Upload and Remove Cover Image for admins (Jellyfin's image endpoints need admin), and Shuffle
/// Cover while the cover is generated.
struct CoverMenuItems: View {
    @Environment(\.theme) private var theme
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    let itemID: String
    let imageTag: String?
    let owner: LibraryEditor.CoverOwner
    @Binding var pickingCover: String?

    var body: some View {
        if store.isAdmin {
            Button("Upload Cover Image", glyph: .photo) { pickingCover = itemID }
                .requiresServer()
        }
        if imageTag == nil {
            Button("Shuffle Cover", glyph: .shuffle) {
                withAnimation(theme.motion.snappy) { store.shuffleCover(for: itemID) }
            }
        } else if store.isAdmin {
            Button("Remove Cover Image", glyph: .close) {
                Task {
                    do { try await store.editor.removeCoverImage(itemID: itemID, owner: owner) } catch {
                        actions.editFailed("remove this cover", error)
                    }
                }
            }
            .requiresServer()
        }
    }
}

private struct CoverImagePicker: ViewModifier {
    @Environment(LibraryStore.self) private var store
    @Environment(LibraryActions.self) private var actions
    @Binding var itemID: String?
    let owner: LibraryEditor.CoverOwner
    @State private var selection: PhotosPickerItem?
    /// Kept past dismissal: the binding clears when the picker closes, before the photo loads.
    @State private var target: String?

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: Binding(get: { itemID != nil }, set: { if !$0 { itemID = nil } }),
                selection: $selection,
                matching: .images
            )
            .onChange(of: itemID) { _, id in if let id { target = id } }
            .onChange(of: selection) { _, item in
                guard let item, let id = target else { return }
                selection = nil
                upload(item, to: id)
            }
    }

    private func upload(_ item: PhotosPickerItem, to id: String) {
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let jpeg = await Self.squareJPEG(data) else {
                    actions.errorMessage = "Couldn't read that image."
                    return
                }
                try await store.editor.setCoverImage(itemID: id, jpeg: jpeg, owner: owner)
                actions.confirm("Cover updated")
            } catch {
                actions.editFailed("change this cover", error)
            }
        }
    }

    /// Center-cropped square JPEG, at most 1200px: plenty for the detail page, small to upload.
    /// ImageIO decodes straight to a thumbnail whose short side is 1200px (orientation applied),
    /// so a 48MP photo never becomes a full-size bitmap in memory.
    @concurrent private static func squareJPEG(_ data: Data) async -> Data? {
        let side = 1200.0
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0 else { return nil }
        let longest = max(width, height), shortest = min(width, height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(longest, (side * longest / shortest).rounded(.up)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let crop = min(image.width, image.height)
        let rect = CGRect(x: (image.width - crop) / 2, y: (image.height - crop) / 2, width: crop, height: crop)
        guard let square = image.cropping(to: rect) else { return nil }
        return UIImage(cgImage: square).jpegData(compressionQuality: 0.85)
    }
}
