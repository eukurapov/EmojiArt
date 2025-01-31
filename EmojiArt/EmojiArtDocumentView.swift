//
//  EmojiArtDocumentView.swift
//  EmojiArt
//
//  Created by CS193p Instructor on 4/27/20.
//  Copyright © 2020 Stanford University. All rights reserved.
//

import SwiftUI

struct EmojiArtDocumentView: View {
    @ObservedObject var document: EmojiArtDocument
    
    var body: some View {
        VStack {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(EmojiArtDocument.palette.map { String($0) }, id: \.self) { emoji in
                        Text(emoji)
                            .font(Font.system(size: self.defaultEmojiSize))
                            .onDrag { NSItemProvider(object: emoji as NSString) }
                    }
                }
            }
            .padding(.horizontal)
            GeometryReader { geometry in
                ZStack {
                    Color.white.overlay(
                        OptionalImage(uiImage: self.document.backgroundImage)
                            .scaleEffect(self.zoomScale)
                            .offset(self.panOffset)
                    )
                        .gesture(self.doubleTapToZoom(in: geometry.size).simultaneously(with: TapGesture().onEnded {
                            self.document.clearSelection()
                        }))
                    ForEach(self.document.emojis) { emoji in
                        Text(emoji.text)
                            .font(animatableWithSize: emoji.fontSize * (self.document.isSelected(emoji: emoji) ? self.selectionZoomScale : self.zoomScale))
                            .border(self.document.isSelected(emoji: emoji) ? Color.gray : Color.clear)
                            .position(self.position(for: emoji, in: geometry.size))
                            .gesture(self.dragGesture(for: self.document.isSelected(emoji: emoji) ? nil : emoji))
                            .onTapGesture(count: 3) {
                                self.document.removeEmoji(emoji)
                        }
                            .onTapGesture {
                                self.document.select(emoji: emoji)
                        }
                    }
                }
                .clipped()
                .gesture(self.panGesture())
                .gesture(self.zoomGesture())
                .edgesIgnoringSafeArea([.horizontal, .bottom])
                .onDrop(of: ["public.image","public.text"], isTargeted: nil) { providers, location in
                    // SwiftUI bug (as of 13.4)? the location is supposed to be in our coordinate system
                    // however, the y coordinate appears to be in the global coordinate system
                    var location = CGPoint(x: location.x, y: geometry.convert(location, from: .global).y)
                    location = CGPoint(x: location.x - geometry.size.width/2, y: location.y - geometry.size.height/2)
                    location = CGPoint(x: location.x - self.panOffset.width, y: location.y - self.panOffset.height)
                    location = CGPoint(x: location.x / self.zoomScale, y: location.y / self.zoomScale)
                    return self.drop(providers: providers, at: location)
                }
            }
        }
    }
    
    @State private var steadyStateZoomScale: CGFloat = 1.0
    @GestureState private var gestureZoomScale: CGFloat = 1.0
    @GestureState private var gestureSelectedZoomScale: CGFloat = 1.0
    
    private var zoomScale: CGFloat {
        steadyStateZoomScale * gestureZoomScale
    }
    
    private var selectionZoomScale: CGFloat {
        gestureSelectedZoomScale * zoomScale
    }
    
    private func zoomGesture() -> some Gesture {
        if document.selectedEmojis.isEmpty {
            return MagnificationGesture()
                .updating($gestureZoomScale) { latestGestureScale, gestureZoomScale, transaction in
                    gestureZoomScale = latestGestureScale
            }
            .onEnded { finalGestureScale in
                self.steadyStateZoomScale *= finalGestureScale
            }
        } else {
            return MagnificationGesture()
                .updating($gestureSelectedZoomScale) { latestGestureScale, gestureSelectedZoomScale, transaction in
                    gestureSelectedZoomScale = latestGestureScale
            }
            .onEnded { finalGestureScale in
                self.document.scaleSelection(by: finalGestureScale)
            }
        }
    }
    
    @State private var steadyStatePanOffset: CGSize = .zero
    @GestureState private var gesturePanOffset: CGSize = .zero
    
    private var panOffset: CGSize {
        (steadyStatePanOffset + gesturePanOffset) * zoomScale
    }
    
    private func panGesture() -> some Gesture {
        DragGesture()
            .updating($gesturePanOffset) { latestDragGestureValue, gesturePanOffset, transaction in
                gesturePanOffset = latestDragGestureValue.translation / self.zoomScale
        }
        .onEnded { finalDragGestureValue in
            self.steadyStatePanOffset = self.steadyStatePanOffset + (finalDragGestureValue.translation / self.zoomScale)
        }
    }
    
    @GestureState private var gestureDragOffset: CGSize = .zero
    @State private var draggingEmoji: EmojiArt.Emoji? = nil
    
    private var dragOffset: CGSize {
        gestureDragOffset * zoomScale
    }
    
    private func dragGesture(for emoji: EmojiArt.Emoji? = nil) -> some Gesture {
        return DragGesture()
        .onChanged { _ in
            self.draggingEmoji = emoji
        }
            .updating($gestureDragOffset) { latestDragGestureValue, gestureDragOffset, transaction in
                gestureDragOffset = latestDragGestureValue.translation / self.zoomScale
        }
        .onEnded { finalDragGestureValue in
            if let emoji = emoji {
                self.document.moveEmoji(emoji, by: finalDragGestureValue.translation / self.zoomScale)
            } else {
                self.document.moveSelection(by: finalDragGestureValue.translation / self.zoomScale)
            }
        }
    }
    
    private func doubleTapToZoom(in size: CGSize) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation {
                    self.zoomToFit(self.document.backgroundImage, in: size)
                }
        }
    }
    
    private func zoomToFit(_ image: UIImage?, in size: CGSize) {
        if let image = image, image.size.width > 0, image.size.height > 0 {
            let hZoom = size.width / image.size.width
            let vZoom = size.height / image.size.height
            self.steadyStatePanOffset = .zero
            self.steadyStateZoomScale = min(hZoom, vZoom)
        }
    }
    
    private func position(for emoji: EmojiArt.Emoji, in size: CGSize) -> CGPoint {
        var location = emoji.location
        location = CGPoint(x: location.x * zoomScale, y: location.y * zoomScale)
        location = CGPoint(x: location.x + size.width/2, y: location.y + size.height/2)
        location = CGPoint(x: location.x + panOffset.width, y: location.y + panOffset.height)
        if document.isSelected(emoji: emoji) && draggingEmoji == nil || draggingEmoji?.id == emoji.id {
            location = CGPoint(x: location.x + dragOffset.width, y: location.y + dragOffset.height)
        }
        return location
    }
    
    private func drop(providers: [NSItemProvider], at location: CGPoint) -> Bool {
        var found = providers.loadFirstObject(ofType: URL.self) { url in
            self.document.setBackgroundURL(url)
        }
        if !found {
            found = providers.loadObjects(ofType: String.self) { string in
                self.document.addEmoji(string, at: location, size: self.defaultEmojiSize)
            }
        }
        return found
    }
    
    private let defaultEmojiSize: CGFloat = 40
}
