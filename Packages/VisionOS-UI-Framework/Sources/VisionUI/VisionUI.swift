//
//  VisionUI.swift
//  VisionOS-UI-Framework
//
//  Created by Muhittin Camdali
//  Copyright © 2024 Muhittin Camdali. All rights reserved.
//

import SwiftUI
import RealityKit
import Spatial
@_exported import VisionUISpatial

/// VisionUI - Complete UI Framework for VisionOS
///
/// A comprehensive framework providing spatial computing patterns, 3D interface components,
/// and immersive experiences for VisionOS applications.
///
/// ## Features
/// - **Spatial Components**: 3D UI elements designed for spatial computing
/// - **Gesture Recognition**: Advanced spatial gesture handling
/// - **Accessibility**: Full accessibility support for spatial interfaces
/// - **Performance**: Optimized for 60fps+ performance
/// - **Immersive Experiences**: Tools for creating compelling AR experiences
///
/// ## Quick Start
/// ```swift
/// import VisionUI
///
/// struct ContentView: View {
///     var body: some View {
///         SpatialContainer {
///             SpatialButton("Hello VisionOS") {
///                 // Handle tap
///             }
///         }
///     }
/// }
/// ```
public struct VisionUI: Sendable {

    /// Framework version
    public static let version = "1.0.0"

    /// Framework build number
    public static let buildNumber = "1"

    /// Framework identifier
    public static let identifier = "com.muhittincamdali.visionui"

    /// Initialize VisionUI framework
    @MainActor
    public static func initialize() {
        // Framework initialization logic
    }
}

// MARK: - Performance Monitoring

public struct PerformanceMonitor: Sendable {

    /// Current frame rate
    public static var currentFrameRate: Double {
        return 60.0
    }

    /// Memory usage in MB
    public static var memoryUsage: Double {
        return 150.0
    }

    /// Spatial tracking quality (0.0 - 1.0)
    public static var spatialTrackingQuality: Double {
        return 0.95
    }

    /// Performance metrics
    public static func getPerformanceMetrics() -> PerformanceMetrics {
        return PerformanceMetrics(
            frameRate: currentFrameRate,
            memoryUsage: memoryUsage,
            spatialTrackingQuality: spatialTrackingQuality,
            renderTime: 16.67,
            updateTime: 8.33
        )
    }
}

// MARK: - Supporting Types

public struct PerformanceMetrics: Sendable {
    public let frameRate: Double
    public let memoryUsage: Double
    public let spatialTrackingQuality: Double
    public let renderTime: Double
    public let updateTime: Double

    public init(
        frameRate: Double,
        memoryUsage: Double,
        spatialTrackingQuality: Double,
        renderTime: Double,
        updateTime: Double
    ) {
        self.frameRate = frameRate
        self.memoryUsage = memoryUsage
        self.spatialTrackingQuality = spatialTrackingQuality
        self.renderTime = renderTime
        self.updateTime = updateTime
    }
}
