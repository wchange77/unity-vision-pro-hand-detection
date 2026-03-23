//
//  SpatialComponents.swift
//  VisionOS-UI-Framework
//
//  Created by Muhittin Camdali
//  Copyright © 2024 Muhittin Camdali. All rights reserved.
//

import SwiftUI
import RealityKit

/// Spatial Components for VisionOS
public struct SpatialComponents {

    /// A container that provides spatial context for 3D UI elements
    @MainActor
    public struct SpatialContainer<Content: View>: View {
        private let content: Content

        public init(
            @ViewBuilder content: () -> Content
        ) {
            self.content = content()
        }

        public var body: some View {
            VStack {
                content
            }
            .glassBackgroundEffect()
        }
    }

    /// A 3D button designed for spatial interaction
    @MainActor
    public struct SpatialButton: View {
        private let title: String
        private let action: () -> Void
        private let style: SpatialButtonStyle

        public init(
            _ title: String,
            style: SpatialButtonStyle = .primary,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.style = style
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(style.textColor)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(style.backgroundColor)
                            .shadow(color: style.shadowColor, radius: 8, x: 0, y: 4)
                    )
            }
            .buttonStyle(SpatialButtonStyleModifier(style: style))
        }
    }

    /// A 3D card component for displaying content in spatial environments
    @MainActor
    public struct SpatialCard<Content: View>: View {
        private let content: Content
        private let style: SpatialCardStyle

        public init(
            style: SpatialCardStyle = .default,
            @ViewBuilder content: () -> Content
        ) {
            self.style = style
            self.content = content()
        }

        public var body: some View {
            VStack(spacing: 16) {
                content
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(style.backgroundColor)
                    .shadow(color: style.shadowColor, radius: 12, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(style.borderColor, lineWidth: 1)
            )
        }
    }

    /// A spatial navigation component for 3D environments
    @MainActor
    public struct SpatialNavigation<Content: View>: View {
        private let title: String
        private let content: Content
        private let leadingButton: (() -> AnyView)?
        private let trailingButton: (() -> AnyView)?

        public init(
            title: String,
            leadingButton: (() -> AnyView)? = nil,
            trailingButton: (() -> AnyView)? = nil,
            @ViewBuilder content: () -> Content
        ) {
            self.title = title
            self.leadingButton = leadingButton
            self.trailingButton = trailingButton
            self.content = content()
        }

        public var body: some View {
            VStack(spacing: 0) {
                HStack {
                    if let leadingButton = leadingButton {
                        leadingButton()
                    }

                    Spacer()

                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Spacer()

                    if let trailingButton = trailingButton {
                        trailingButton()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                )

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// A 3D list component for spatial environments
    @MainActor
    public struct SpatialList<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
        private let data: Data
        private let content: (Data.Element) -> Content
        private let style: SpatialListStyle

        public init(
            _ data: Data,
            style: SpatialListStyle = .default,
            @ViewBuilder content: @escaping (Data.Element) -> Content
        ) {
            self.data = data
            self.style = style
            self.content = content
        }

        public var body: some View {
            ScrollView {
                LazyVStack(spacing: style.itemSpacing) {
                    ForEach(data) { item in
                        content(item)
                            .padding(.horizontal, style.horizontalPadding)
                    }
                }
                .padding(.vertical, style.verticalPadding)
            }
            .background(style.backgroundColor)
        }
    }

    /// A 3D modal component for spatial interfaces
    @MainActor
    public struct SpatialModal<Content: View>: View {
        private let isPresented: Binding<Bool>
        private let content: Content
        private let style: SpatialModalStyle

        public init(
            isPresented: Binding<Bool>,
            style: SpatialModalStyle = .default,
            @ViewBuilder content: () -> Content
        ) {
            self.isPresented = isPresented
            self.style = style
            self.content = content()
        }

        public var body: some View {
            if isPresented.wrappedValue {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isPresented.wrappedValue = false
                            }
                        }

                    VStack(spacing: 20) {
                        content
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(style.backgroundColor)
                            .shadow(color: style.shadowColor, radius: 20, x: 0, y: 10)
                    )
                    .scaleEffect(isPresented.wrappedValue ? 1.0 : 0.8)
                    .opacity(isPresented.wrappedValue ? 1.0 : 0.0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isPresented.wrappedValue)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
    }
}

// MARK: - Supporting Types

public struct SpatialButtonStyle: Sendable {
    public let backgroundColor: Color
    public let textColor: Color
    public let shadowColor: Color
    public let pressedColor: Color

    public init(
        backgroundColor: Color,
        textColor: Color,
        shadowColor: Color,
        pressedColor: Color
    ) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.shadowColor = shadowColor
        self.pressedColor = pressedColor
    }

    public static let primary = SpatialButtonStyle(
        backgroundColor: .blue,
        textColor: .white,
        shadowColor: .blue.opacity(0.3),
        pressedColor: .blue.opacity(0.8)
    )

    public static let secondary = SpatialButtonStyle(
        backgroundColor: .gray.opacity(0.2),
        textColor: .primary,
        shadowColor: .gray.opacity(0.2),
        pressedColor: .gray.opacity(0.3)
    )

    public static let success = SpatialButtonStyle(
        backgroundColor: .green,
        textColor: .white,
        shadowColor: .green.opacity(0.3),
        pressedColor: .green.opacity(0.8)
    )

    public static let danger = SpatialButtonStyle(
        backgroundColor: .red,
        textColor: .white,
        shadowColor: .red.opacity(0.3),
        pressedColor: .red.opacity(0.8)
    )
}

public struct SpatialCardStyle: Sendable {
    public let backgroundColor: Color
    public let shadowColor: Color
    public let borderColor: Color

    public init(
        backgroundColor: Color,
        shadowColor: Color,
        borderColor: Color
    ) {
        self.backgroundColor = backgroundColor
        self.shadowColor = shadowColor
        self.borderColor = borderColor
    }

    public static let `default` = SpatialCardStyle(
        backgroundColor: Color(.systemBackground).opacity(0.1),
        shadowColor: .black.opacity(0.1),
        borderColor: .clear
    )

    public static let elevated = SpatialCardStyle(
        backgroundColor: Color(.systemBackground).opacity(0.2),
        shadowColor: .black.opacity(0.15),
        borderColor: .gray.opacity(0.2)
    )
}

public struct SpatialListStyle: Sendable {
    public let backgroundColor: Color
    public let itemSpacing: CGFloat
    public let horizontalPadding: CGFloat
    public let verticalPadding: CGFloat

    public init(
        backgroundColor: Color,
        itemSpacing: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat
    ) {
        self.backgroundColor = backgroundColor
        self.itemSpacing = itemSpacing
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    public static let `default` = SpatialListStyle(
        backgroundColor: .clear,
        itemSpacing: 12,
        horizontalPadding: 16,
        verticalPadding: 16
    )

    public static let compact = SpatialListStyle(
        backgroundColor: .clear,
        itemSpacing: 8,
        horizontalPadding: 12,
        verticalPadding: 12
    )
}

public struct SpatialModalStyle: Sendable {
    public let backgroundColor: Color
    public let shadowColor: Color

    public init(
        backgroundColor: Color,
        shadowColor: Color
    ) {
        self.backgroundColor = backgroundColor
        self.shadowColor = shadowColor
    }

    public static let `default` = SpatialModalStyle(
        backgroundColor: Color(.systemBackground).opacity(0.1),
        shadowColor: .black.opacity(0.2)
    )

    public static let elevated = SpatialModalStyle(
        backgroundColor: Color(.systemBackground).opacity(0.2),
        shadowColor: .black.opacity(0.3)
    )
}

private struct SpatialButtonStyleModifier: ButtonStyle {
    let style: SpatialButtonStyle

    nonisolated func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(configuration.isPressed ? style.pressedColor : style.backgroundColor)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
