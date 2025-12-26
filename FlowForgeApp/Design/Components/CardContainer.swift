import SwiftUI

// MARK: - Card Container
// Unified card abstraction per Jony Ive's recommendation.
// "Every card in the app should use this. No exceptions."
//
// Enforces consistent: padding, background, corner radius, shadow.

struct CardContainer<Content: View>: View {
    enum Elevation {
        case base       // Default card
        case lifted     // Hoverable, interactive
        case highlighted // Active, selected

        var background: Color {
            Surface.elevated
        }

        var shadowRadius: CGFloat {
            switch self {
            case .base: return 2
            case .lifted: return 4
            case .highlighted: return 6
            }
        }

        var shadowOpacity: Double {
            switch self {
            case .base: return 0.08
            case .lifted: return 0.12
            case .highlighted: return 0.15
            }
        }
    }

    let elevation: Elevation
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        elevation: Elevation = .base,
        padding: CGFloat = Spacing.medium,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.elevation = elevation
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(elevation.background)
            .cornerRadius(CornerRadius.large)
            .shadow(
                color: .black.opacity(elevation.shadowOpacity),
                radius: elevation.shadowRadius,
                x: 0,
                y: elevation.shadowRadius / 2
            )
    }
}

// MARK: - Card Modifiers

extension View {
    /// Wrap content in a standard card container
    func card(elevation: CardContainer<Self>.Elevation = .base, padding: CGFloat = Spacing.medium) -> some View {
        CardContainer(elevation: elevation, padding: padding) {
            self
        }
    }

    /// Wrap content in a lifted (hoverable) card
    func liftedCard(padding: CGFloat = Spacing.medium) -> some View {
        card(elevation: .lifted, padding: padding)
    }

    /// Wrap content in a highlighted (active) card
    func highlightedCard(padding: CGFloat = Spacing.medium) -> some View {
        card(elevation: .highlighted, padding: padding)
    }
}

// MARK: - Status Card
// Card with a colored left border indicating status

struct StatusCard<Content: View>: View {
    let status: FeatureStatus
    let elevation: CardContainer<Content>.Elevation
    @ViewBuilder let content: () -> Content

    init(
        status: FeatureStatus,
        elevation: CardContainer<Content>.Elevation = .base,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.status = status
        self.elevation = elevation
        self.content = content
    }

    var body: some View {
        HStack(spacing: 0) {
            // Status indicator - left border
            Rectangle()
                .fill(statusColor)
                .frame(width: 4)

            // Content
            content()
                .padding(Spacing.medium)
        }
        .background(CardContainer<Content>.Elevation.base.background)
        .cornerRadius(CornerRadius.large)
        .shadow(
            color: .black.opacity(elevation.shadowOpacity),
            radius: elevation.shadowRadius,
            x: 0,
            y: elevation.shadowRadius / 2
        )
    }

    private var statusColor: Color {
        switch status {
        case .planned: return StatusColor.planned
        case .inProgress: return StatusColor.inProgress
        case .review: return StatusColor.review
        case .completed: return StatusColor.completed
        case .blocked: return StatusColor.blocked
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CardContainerPreview: View {
    var body: some View {
        VStack(spacing: Spacing.large) {
            Text("CARD CONTAINERS")
                .sectionHeaderStyle()

            // Elevation levels
            HStack(spacing: Spacing.medium) {
                CardContainer(elevation: .base) {
                    VStack(alignment: .leading) {
                        Text("Base")
                            .font(Typography.featureTitle)
                        Text("Default card style")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 120)
                }

                CardContainer(elevation: .lifted) {
                    VStack(alignment: .leading) {
                        Text("Lifted")
                            .font(Typography.featureTitle)
                        Text("Hoverable cards")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 120)
                }

                CardContainer(elevation: .highlighted) {
                    VStack(alignment: .leading) {
                        Text("Highlighted")
                            .font(Typography.featureTitle)
                        Text("Active/selected")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 120)
                }
            }

            Divider()

            // Status cards
            VStack(spacing: Spacing.small) {
                StatusCard(status: .planned) {
                    Text("Planned feature")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                StatusCard(status: .inProgress) {
                    Text("In progress feature")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                StatusCard(status: .review) {
                    Text("Ready for review")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                StatusCard(status: .completed) {
                    Text("Shipped!")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: 300)

            Divider()

            // Modifier syntax
            Text("Using .card() modifier")
                .card()

            Text("Using .liftedCard() modifier")
                .liftedCard()
        }
        .padding(Spacing.large)
        .frame(width: 500, height: 600)
        .background(Surface.window)
    }
}

#Preview {
    CardContainerPreview()
}
#endif
