//
//  SpatialGestures.swift
//  VisionOS-UI-Framework
//
//  Created by Muhittin Camdali
//  Copyright © 2024 Muhittin Camdali. All rights reserved.
//

import SwiftUI

/// Spatial Gesture Recognition System for VisionOS
public struct SpatialGestures {

    /// A spatial tap gesture recognizer for 3D environments
    @MainActor
    public struct SpatialTapGesture: ViewModifier {
        private let action: () -> Void
        private let minimumDistance: Double
        private let maximumDistance: Double

        public init(
            minimumDistance: Double = 0.1,
            maximumDistance: Double = 2.0,
            action: @escaping () -> Void
        ) {
            self.minimumDistance = minimumDistance
            self.maximumDistance = maximumDistance
            self.action = action
        }

        public func body(content: Content) -> some View {
            content
                .gesture(
                    TapGesture()
                        .onEnded { _ in
                            action()
                        }
                )
        }
    }

    /// A spatial drag gesture recognizer for 3D manipulation
    @MainActor
    public struct SpatialDragGesture: ViewModifier {
        private let onChanged: (SpatialDragValue) -> Void
        private let onEnded: (SpatialDragValue) -> Void
        private let minimumDistance: Double
        private let maximumDistance: Double

        public init(
            minimumDistance: Double = 0.1,
            maximumDistance: Double = 5.0,
            onChanged: @escaping (SpatialDragValue) -> Void = { _ in },
            onEnded: @escaping (SpatialDragValue) -> Void = { _ in }
        ) {
            self.minimumDistance = minimumDistance
            self.maximumDistance = maximumDistance
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        public func body(content: Content) -> some View {
            content
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let dragValue = SpatialDragValue(
                                translation: [Double(value.translation.width), Double(value.translation.height), 0],
                                velocity: [0, 0, 0],
                                startLocation: [Double(value.startLocation.x), Double(value.startLocation.y), 0],
                                currentLocation: [Double(value.location.x), Double(value.location.y), 0],
                                distance: sqrt(Double(value.translation.width * value.translation.width + value.translation.height * value.translation.height))
                            )
                            onChanged(dragValue)
                        }
                        .onEnded { value in
                            let dragValue = SpatialDragValue(
                                translation: [Double(value.translation.width), Double(value.translation.height), 0],
                                velocity: [0, 0, 0],
                                startLocation: [Double(value.startLocation.x), Double(value.startLocation.y), 0],
                                currentLocation: [Double(value.location.x), Double(value.location.y), 0],
                                distance: sqrt(Double(value.translation.width * value.translation.width + value.translation.height * value.translation.height))
                            )
                            onEnded(dragValue)
                        }
                )
        }
    }

    /// A spatial pinch gesture recognizer for scaling operations
    @MainActor
    public struct SpatialPinchGesture: ViewModifier {
        private let onChanged: (SpatialPinchValue) -> Void
        private let onEnded: (SpatialPinchValue) -> Void
        private let minimumScale: Double
        private let maximumScale: Double

        public init(
            minimumScale: Double = 0.1,
            maximumScale: Double = 10.0,
            onChanged: @escaping (SpatialPinchValue) -> Void = { _ in },
            onEnded: @escaping (SpatialPinchValue) -> Void = { _ in }
        ) {
            self.minimumScale = minimumScale
            self.maximumScale = maximumScale
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        public func body(content: Content) -> some View {
            content
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let pinchValue = SpatialPinchValue(
                                scale: Double(value.magnification),
                                velocity: 0,
                                startScale: 1.0,
                                currentScale: Double(value.magnification)
                            )
                            onChanged(pinchValue)
                        }
                        .onEnded { value in
                            let pinchValue = SpatialPinchValue(
                                scale: Double(value.magnification),
                                velocity: 0,
                                startScale: 1.0,
                                currentScale: Double(value.magnification)
                            )
                            onEnded(pinchValue)
                        }
                )
        }
    }

    /// A spatial rotation gesture recognizer for 3D rotation
    @MainActor
    public struct SpatialRotationGesture: ViewModifier {
        private let onChanged: (SpatialRotationValue) -> Void
        private let onEnded: (SpatialRotationValue) -> Void
        private let minimumRotation: Double
        private let maximumRotation: Double

        public init(
            minimumRotation: Double = 0.1,
            maximumRotation: Double = .pi * 2,
            onChanged: @escaping (SpatialRotationValue) -> Void = { _ in },
            onEnded: @escaping (SpatialRotationValue) -> Void = { _ in }
        ) {
            self.minimumRotation = minimumRotation
            self.maximumRotation = maximumRotation
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        public func body(content: Content) -> some View {
            content
                .gesture(
                    RotateGesture()
                        .onChanged { value in
                            let rotationValue = SpatialRotationValue(
                                rotation: value.rotation.radians,
                                velocity: 0,
                                startRotation: 0,
                                currentRotation: value.rotation.radians
                            )
                            onChanged(rotationValue)
                        }
                        .onEnded { value in
                            let rotationValue = SpatialRotationValue(
                                rotation: value.rotation.radians,
                                velocity: 0,
                                startRotation: 0,
                                currentRotation: value.rotation.radians
                            )
                            onEnded(rotationValue)
                        }
                )
        }
    }

    /// A spatial hover gesture recognizer for hover interactions
    @MainActor
    public struct SpatialHoverGesture: ViewModifier {
        private let onEntered: () -> Void
        private let onExited: () -> Void
        private let onMoved: (SpatialHoverValue) -> Void
        private let hoverDistance: Double

        public init(
            hoverDistance: Double = 0.5,
            onEntered: @escaping () -> Void = {},
            onExited: @escaping () -> Void = {},
            onMoved: @escaping (SpatialHoverValue) -> Void = { _ in }
        ) {
            self.hoverDistance = hoverDistance
            self.onEntered = onEntered
            self.onExited = onExited
            self.onMoved = onMoved
        }

        public func body(content: Content) -> some View {
            content
                .onHover { isHovering in
                    if isHovering {
                        onEntered()
                    } else {
                        onExited()
                    }
                }
        }
    }

    /// A spatial long press gesture recognizer for context menus
    @MainActor
    public struct SpatialLongPressGesture: ViewModifier {
        private let minimumDuration: Double
        private let maximumDistance: Double
        private let action: () -> Void

        public init(
            minimumDuration: Double = 0.5,
            maximumDistance: Double = 0.2,
            action: @escaping () -> Void
        ) {
            self.minimumDuration = minimumDuration
            self.maximumDistance = maximumDistance
            self.action = action
        }

        public func body(content: Content) -> some View {
            content
                .gesture(
                    LongPressGesture(minimumDuration: minimumDuration)
                        .onEnded { _ in
                            action()
                        }
                )
        }
    }
}

// MARK: - Supporting Types

public struct SpatialDragValue: Sendable {
    public let translation: [Double]
    public let velocity: [Double]
    public let startLocation: [Double]
    public let currentLocation: [Double]
    public let distance: Double

    public init(
        translation: [Double],
        velocity: [Double],
        startLocation: [Double],
        currentLocation: [Double],
        distance: Double
    ) {
        self.translation = translation
        self.velocity = velocity
        self.startLocation = startLocation
        self.currentLocation = currentLocation
        self.distance = distance
    }
}

public struct SpatialPinchValue: Sendable {
    public let scale: Double
    public let velocity: Double
    public let startScale: Double
    public let currentScale: Double

    public init(
        scale: Double,
        velocity: Double,
        startScale: Double,
        currentScale: Double
    ) {
        self.scale = scale
        self.velocity = velocity
        self.startScale = startScale
        self.currentScale = currentScale
    }
}

public struct SpatialRotationValue: Sendable {
    public let rotation: Double
    public let velocity: Double
    public let startRotation: Double
    public let currentRotation: Double

    public init(
        rotation: Double,
        velocity: Double,
        startRotation: Double,
        currentRotation: Double
    ) {
        self.rotation = rotation
        self.velocity = velocity
        self.startRotation = startRotation
        self.currentRotation = currentRotation
    }
}

public struct SpatialHoverValue: Sendable {
    public let location: [Double]
    public let distance: Double
    public let velocity: [Double]

    public init(
        location: [Double],
        distance: Double,
        velocity: [Double]
    ) {
        self.location = location
        self.distance = distance
        self.velocity = velocity
    }
}

// MARK: - View Extensions

public extension View {

    /// Add spatial tap gesture to the view
    func spatialTap(
        minimumDistance: Double = 0.1,
        maximumDistance: Double = 2.0,
        action: @escaping () -> Void
    ) -> some View {
        modifier(SpatialGestures.SpatialTapGesture(
            minimumDistance: minimumDistance,
            maximumDistance: maximumDistance,
            action: action
        ))
    }

    /// Add spatial drag gesture to the view
    func spatialDrag(
        minimumDistance: Double = 0.1,
        maximumDistance: Double = 5.0,
        onChanged: @escaping (SpatialDragValue) -> Void = { _ in },
        onEnded: @escaping (SpatialDragValue) -> Void = { _ in }
    ) -> some View {
        modifier(SpatialGestures.SpatialDragGesture(
            minimumDistance: minimumDistance,
            maximumDistance: maximumDistance,
            onChanged: onChanged,
            onEnded: onEnded
        ))
    }

    /// Add spatial pinch gesture to the view
    func spatialPinch(
        minimumScale: Double = 0.1,
        maximumScale: Double = 10.0,
        onChanged: @escaping (SpatialPinchValue) -> Void = { _ in },
        onEnded: @escaping (SpatialPinchValue) -> Void = { _ in }
    ) -> some View {
        modifier(SpatialGestures.SpatialPinchGesture(
            minimumScale: minimumScale,
            maximumScale: maximumScale,
            onChanged: onChanged,
            onEnded: onEnded
        ))
    }

    /// Add spatial rotation gesture to the view
    func spatialRotation(
        minimumRotation: Double = 0.1,
        maximumRotation: Double = .pi * 2,
        onChanged: @escaping (SpatialRotationValue) -> Void = { _ in },
        onEnded: @escaping (SpatialRotationValue) -> Void = { _ in }
    ) -> some View {
        modifier(SpatialGestures.SpatialRotationGesture(
            minimumRotation: minimumRotation,
            maximumRotation: maximumRotation,
            onChanged: onChanged,
            onEnded: onEnded
        ))
    }

    /// Add spatial hover gesture to the view
    func spatialHover(
        hoverDistance: Double = 0.5,
        onEntered: @escaping () -> Void = {},
        onExited: @escaping () -> Void = {},
        onMoved: @escaping (SpatialHoverValue) -> Void = { _ in }
    ) -> some View {
        modifier(SpatialGestures.SpatialHoverGesture(
            hoverDistance: hoverDistance,
            onEntered: onEntered,
            onExited: onExited,
            onMoved: onMoved
        ))
    }

    /// Add spatial long press gesture to the view
    func spatialLongPress(
        minimumDuration: Double = 0.5,
        maximumDistance: Double = 0.2,
        action: @escaping () -> Void
    ) -> some View {
        modifier(SpatialGestures.SpatialLongPressGesture(
            minimumDuration: minimumDuration,
            maximumDistance: maximumDistance,
            action: action
        ))
    }
}
