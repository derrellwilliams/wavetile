import DesignSystem
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
        }
        if imageTag == nil {
            Button("Shuffle Cover", glyph: .shuffle) {
                withAnimation(theme.motion.snappy) { store.shuffleCover(for: itemID) }
            }
        } else if store.isAdmin {
            Button("Remove Cover Image", glyph: .close) {
                Task {
                    do { try await store.editor.removeCoverImage(itemID: itemID, owner: owner) } catch {
                        Log.editFailed("Remove cover", error)
                        actions.errorMessage = "Couldn't remove the cover. Check your connection."
                    }
                }
            }
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
                Log.editFailed("Upload cover", error)
                actions.errorMessage = "Couldn't change the cover. Your Jellyfin account may not be allowed to edit images."
            }
        }
    }

    /// Center-cropped square JPEG, at most 1200px: plenty for the detail page, small to upload.
    @concurrent private static func squareJPEG(_ data: Data) async -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = min(1200, min(image.size.width, image.size.height) * image.scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let fill = side / min(image.size.width, image.size.height)
            let size = CGSize(width: image.size.width * fill, height: image.size.height * fill)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        return rendered.jpegData(compressionQuality: 0.85)
    }
}
