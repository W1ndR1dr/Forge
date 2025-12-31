import SwiftUI

// MARK: - Design Tokens
// Influenced by: Dieter Rams (systematic), Edward Tufte (semantic), Jony Ive (considered)
//
// "Good design is as little design as possible" — Dieter Rams
// Every token serves a purpose. Nothing decorative.

// MARK: - Color System

/// Semantic status colors — the color IS the information (Tufte)
enum StatusColor {
    /// Inbox: Quick capture, raw thoughts — creative purple
    static let inbox = Color("StatusInbox", bundle: nil)
    static let inboxFallback = Color(light: .purple.opacity(0.8), dark: .purple)

    /// Idea: Refined, ready to build — subdued, patient
    static let idea = Color("StatusIdea", bundle: nil)
    static let ideaFallback = Color(light: .init(white: 0.45), dark: .init(white: 0.55))

    /// In Progress: Active work, attention here — confident blue
    static let inProgress = Color("StatusInProgress", bundle: nil)
    static let inProgressFallback = Color(light: .blue, dark: .init(red: 0.4, green: 0.6, blue: 1.0))

    /// Review: Almost done, needs final check — warm amber
    static let review = Color("StatusReview", bundle: nil)
    static let reviewFallback = Color(light: .orange, dark: .init(red: 1.0, green: 0.7, blue: 0.3))

    /// Completed: Shipped, celebration — fresh emerald
    static let completed = Color("StatusCompleted", bundle: nil)
    static let completedFallback = Color(light: .init(red: 0.2, green: 0.7, blue: 0.4), dark: .init(red: 0.3, green: 0.8, blue: 0.5))

    /// Blocked: Problem, needs intervention — alert rose
    static let blocked = Color("StatusBlocked", bundle: nil)
    static let blockedFallback = Color(light: .init(red: 0.9, green: 0.3, blue: 0.3), dark: .init(red: 1.0, green: 0.4, blue: 0.4))

    static func color(for status: FeatureStatus) -> Color {
        switch status {
        case .inbox: return inboxFallback
        case .idea: return ideaFallback
        case .inProgress: return inProgressFallback
        case .review: return reviewFallback
        case .completed: return completedFallback
        case .blocked: return blockedFallback
        }
    }
}

/// Complexity indicators — size feeling through visual weight (Tufte)
enum ComplexityColor {
    /// Small: Quick win, ship today — light, encouraging
    static let small = Color.green.opacity(0.8)

    /// Medium: Half-day to full day — balanced, neutral
    static let medium = Color.orange.opacity(0.8)

    /// Large: Multi-day, needs planning — heavier, attention
    static let large = Color.red.opacity(0.8)

    /// Epic: Should be broken down — outlined, warning
    static let epic = Color.purple.opacity(0.6)
}

/// Surface hierarchy — Ive's layered depth thinking
enum Surface {
    /// Base window background — respects system appearance
    static var window: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    /// Elevated surface (+1 level) — cards, containers
    static var elevated: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    /// Highlighted surface (+2 level) — active card, focus
    static var highlighted: Color {
        #if os(macOS)
        Color(nsColor: .selectedContentBackgroundColor).opacity(0.3)
        #else
        Color(uiColor: .tertiarySystemBackground)
        #endif
    }

    /// Overlay with blur — modals, sheets
    static let overlay = Color.black.opacity(0.4)
}

/// Accent colors for actions and emphasis
enum Accent {
    /// Primary action color — the SHIP button
    static let primary = Color.blue

    /// Success/celebration — shipping moments
    static let success = Color.green

    /// Warning — approaching limits, streak at risk
    static let warning = Color.orange

    /// Danger — destructive actions, blockers
    static let danger = Color.red

    /// Attention/Gold — priority indicators, non-warning emphasis
    static let attention = Color(hex: "eab308")

    /// Brainstorm/Ideas — refinement, AI assistance
    static let brainstorm = Color.purple

    /// Streak fire — motivation, gamification
    static let streak = Color.orange
}

// MARK: - Typography Scale
// Linear uses Inter for body/UI and Inter Display for headings
// Exact sizes from Linear's web app analysis
//
// "Above all else, show the data" — Tufte

/// Inter font helpers
extension Font {
    /// Inter font with specified size and weight
    /// Falls back to system font if Inter is not available
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }

    /// Inter Display for headings
    static func interDisplay(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("InterDisplay", size: size).weight(weight)
    }
}

enum Typography {
    // MARK: - Headings (Inter Display)

    /// Hero heading - 62px, weight 800 (Black)
    static let hero = Font.interDisplay(62, weight: .black)

    /// Section heading - 20px, weight 600 (Semibold)
    static let sectionHeader = Font.interDisplay(20, weight: .semibold)

    /// Feature title - headline size, semibold
    static let featureTitle = Font.inter(15, weight: .semibold)

    // MARK: - Body (Inter)

    /// Body large - 15-16px
    static let bodyLarge = Font.inter(15, weight: .regular)

    /// Body - 14px (Linear's standard body)
    static let body = Font.inter(14, weight: .regular)

    /// Body medium weight
    static let bodyMedium = Font.inter(14, weight: .medium)

    // MARK: - Labels & Captions

    /// Label/caption - 12px, semibold, used for section labels
    static let label = Font.inter(12, weight: .semibold)

    /// Caption - 12px, regular
    static let caption = Font.inter(12, weight: .regular)

    /// Muted text - 13px
    static let muted = Font.inter(13, weight: .regular)

    /// Badges, tags - 11px, medium
    static let badge = Font.inter(11, weight: .medium)

    // MARK: - Special

    /// Streak number — large, rounded
    static let streakNumber = Font.system(size: 28, weight: .bold, design: .rounded)

    /// Vibe input placeholder
    static let vibeInput = Font.inter(16, weight: .regular)

    /// Monospaced for code
    static let mono = Font.system(size: 13, design: .monospaced)

    // MARK: - Legacy Aliases

    static var largeTitle: Font { sectionHeader }
}

// MARK: - Spacing Scale
// Systematic spacing — Rams' "less, but better"

enum Spacing {
    /// Micro spacing — 4pt (badge internals, tight elements)
    static let micro: CGFloat = 4

    /// Small spacing — 8pt (tag spacing, icon gaps)
    static let small: CGFloat = 8

    /// Medium spacing — 12pt (card internal spacing)
    static let medium: CGFloat = 12

    /// Standard spacing — 16pt (section gaps, card padding)
    static let standard: CGFloat = 16

    /// Large spacing — 24pt (major section gaps)
    static let large: CGFloat = 24

    /// XL spacing — 32pt (view-level separation)
    static let xl: CGFloat = 32
}

// MARK: - Corner Radius
// Linear's precise, tight radii
// Cards: 10px, Buttons: 8px, Inputs: 8px, Popovers: 12px

enum CornerRadius {
    /// Small — 4pt (badges, chips, inline tags)
    static let small: CGFloat = 4

    /// Medium — 6pt (sidebar rows, small interactive elements)
    static let medium: CGFloat = 6

    /// Large — 8pt (buttons, inputs, text fields)
    static let large: CGFloat = 8

    /// XL — 10pt (cards, panels)
    static let xl: CGFloat = 10

    /// XXL — 12pt (popovers, dropdowns, modals)
    static let xxl: CGFloat = 12
}

// MARK: - Shadows
// Linear uses very soft, large-radius shadows with low opacity
// Creates depth without harsh edges

extension View {
    /// Subtle shadow for resting cards
    func linearSubtleShadow() -> some View {
        self.shadow(
            color: Color.black.opacity(0.15),
            radius: 8,
            x: 0,
            y: 2
        )
    }

    /// Card shadow for elevated panels
    func linearCardShadow() -> some View {
        self.shadow(
            color: Color.black.opacity(0.25),
            radius: 20,
            x: 0,
            y: 8
        )
    }

    /// Dropdown/popover shadow
    func linearDropdownShadow() -> some View {
        self.shadow(
            color: Color.black.opacity(0.4),
            radius: 32,
            x: 0,
            y: 16
        )
    }
}

// Legacy Shadow enum for compatibility
enum Shadow {
    static func subtle(_ colorScheme: ColorScheme) -> some View {
        Color.black.opacity(0.15)
    }

    static func elevated(_ colorScheme: ColorScheme) -> some View {
        Color.black.opacity(0.25)
    }

    static let subtleRadius: CGFloat = 8
    static let elevatedRadius: CGFloat = 20
}

// MARK: - Animation Timing
// Mike Matas: "Every animation should feel physical"
// These are base values — AnimationPrimitives.swift has the full system

enum Timing {
    /// Micro-interactions — button press, hover (100ms)
    static let micro: Double = 0.1

    /// State transitions — color change, card move (300ms)
    static let standard: Double = 0.3

    /// Celebrations — confetti, streak (500-800ms)
    static let celebration: Double = 0.5

    /// Long animations — modal appear, graph zoom (400ms)
    static let long: Double = 0.4
}

// MARK: - Linear Design System
// Exact values extracted from Linear's Midnight theme
// Source: linear.app themes, brand guidelines, and UI analysis
//
// Philosophy: opacity-based elevation, perceptual uniformity, ruthless consistency

enum Linear {
    // MARK: - Backgrounds (darkest to lightest)
    // Softened dark greys - easier on the eyes, less harsh contrast

    /// Base window background - softened dark grey (#191919)
    static let background = Color(red: 0.098, green: 0.098, blue: 0.098)

    /// Elevated surface - cards, panels (#1E1E1E)
    static let surface = Color(red: 0.118, green: 0.118, blue: 0.118)

    /// Floating surface - dropdowns, popovers (#242424)
    static let surfaceElevated = Color(hex: "242424")

    /// Modal surface - dialogs, command palette (#282828)
    static let surfaceModal = Color(hex: "282828")

    // MARK: - Interactive States (opacity-based, not solid colors)

    /// Hover background - subtle highlight
    static let hoverBackground = Color.white.opacity(0.06)

    /// Selected/active background
    static let selectedBackground = Color.white.opacity(0.1)

    /// Pressed state background
    static let pressedBackground = Color.white.opacity(0.08)

    // MARK: - Borders (opacity-based for consistency)

    /// Default hairline border
    static let border = Color.white.opacity(0.08)

    /// Hover state border
    static let borderHover = Color.white.opacity(0.12)

    /// Focus state border - uses accent color
    static let borderFocus = Color(hex: "5E6AD2").opacity(0.5)

    // MARK: - Text Hierarchy (softened for reduced contrast)

    /// Primary text - headings, important content (#E0E0E0 - softened from pure white)
    static let textPrimary = Color(red: 0.878, green: 0.878, blue: 0.878)

    /// Secondary text - descriptions, body (#9CA3AF)
    static let textSecondary = Color(red: 0.612, green: 0.639, blue: 0.686)

    /// Tertiary text - metadata, hints (#6B7280)
    static let textTertiary = Color(hex: "6B7280")

    /// Muted text - disabled, placeholders (#52525B)
    static let textMuted = Color(hex: "52525B")

    // MARK: - Accent Colors (Linear's signature indigo)

    /// Primary accent - Linear's signature indigo (#5E6AD2)
    static let accent = Color(hex: "5E6AD2")

    /// Accent hover state (#6872D9)
    static let accentHover = Color(hex: "6872D9")

    /// Accent pressed state (#4551B5)
    static let accentPressed = Color(hex: "4551B5")

    // MARK: - Semantic Colors (muted, desaturated for dark theme)

    /// Success - muted green (#4DA673) at 85% opacity for softer appearance
    static let success = Color(hex: "4DA673").opacity(0.85)

    /// Warning - warm amber (#EAA94B) at 85% opacity
    static let warning = Color(hex: "EAA94B").opacity(0.85)

    /// Error - soft red (#D25E65) at 85% opacity
    static let error = Color(hex: "D25E65").opacity(0.85)

    /// Info - soft blue (same as accent)
    static let info = Color(hex: "5E6AD2").opacity(0.85)

    // MARK: - Legacy Aliases (for migration)
    // TODO: Remove these after updating all views

    static var base: Color { background }
    static var elevated: Color { surface }
    static var card: Color { surface }
    static var hover: Color { hoverBackground }
    static var borderSubtle: Color { border }
    static var borderVisible: Color { borderHover }
}

// MARK: - Helper Extensions

extension Color {
    /// Create a color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }

    /// Create a color that adapts to light/dark mode
    init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        })
        #else
        self.init(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #endif
    }
}

// MARK: - Design Token View Modifiers
// Linear-style modifiers for consistent UI

extension View {
    /// Apply card styling with Linear's elevation system
    func linearCard(isSelected: Bool = false) -> some View {
        self
            .padding(Spacing.standard)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .fill(Linear.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                            .strokeBorder(
                                isSelected ? Linear.accent.opacity(0.5) : Linear.border,
                                lineWidth: 1
                            )
                    )
            )
            .linearSubtleShadow()
    }

    /// Apply badge styling - tight, precise
    func badgeStyle(color: Color) -> some View {
        self
            .font(Typography.badge)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(CornerRadius.small)
    }

    /// Apply section header styling - Linear's uppercase, spaced labels
    func sectionHeaderStyle() -> some View {
        self
            .font(.inter(11, weight: .semibold))
            .foregroundColor(Linear.textSecondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    /// Apply Linear-style section container
    func linearSection() -> some View {
        self
            .padding(Spacing.standard)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .fill(Linear.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                            .strokeBorder(Linear.border, lineWidth: 1)
                    )
            )
    }

    /// Apply popover/dropdown styling
    func linearPopover() -> some View {
        self
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
                    .fill(Linear.surfaceElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
                            .strokeBorder(Linear.border, lineWidth: 1)
                    )
            )
            .linearDropdownShadow()
    }

    /// Linear-style hover modifier with 150ms timing
    func linearHover(isHovered: Bool, radius: CGFloat = CornerRadius.medium) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isHovered ? Linear.hoverBackground : Color.clear)
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // MARK: - Legacy Aliases

    /// Legacy card style
    func cardStyle(isActive: Bool = false) -> some View {
        self.linearCard(isSelected: isActive)
    }
}

// MARK: - Unified DesignTokens Namespace
// Provides a consistent interface for accessing design tokens

enum DesignTokens {
    enum Colors {
        static let primary = Accent.primary
        static let success = Accent.success
        static let warning = Accent.warning
        static let danger = Accent.danger
        static let surface = Surface.elevated
        static let background = Surface.window
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }
}

// MARK: - Linear Button Styles
// Exact patterns from Linear's UI
// - Press scale: 0.97
// - Press duration: 120ms (.snappy(duration: 0.12))
// - Hover duration: 150ms (.easeInOut(duration: 0.15))

/// Primary action button - filled background with accent color
struct LinearPrimaryButtonStyle: ButtonStyle {
    var color: Color = Linear.accent
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(14, weight: .medium))
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed { return Linear.accentPressed }
        if isHovered { return Linear.accentHover }
        return color
    }
}

/// Secondary action button - subtle background with border
struct LinearSecondaryButtonStyle: ButtonStyle {
    var color: Color = Linear.textPrimary
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(14, weight: .medium))
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .foregroundColor(color)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    .strokeBorder(Linear.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed { return Linear.pressedBackground }
        if isHovered { return Linear.hoverBackground }
        return Color.clear
    }
}

/// Ghost button - text only, hover shows subtle background
struct LinearGhostButtonStyle: ButtonStyle {
    var color: Color = Linear.textSecondary
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(14, weight: .medium))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .foregroundColor(color)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .fill(isHovered ? Linear.hoverBackground : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Button Style Extensions

extension ButtonStyle where Self == LinearPrimaryButtonStyle {
    static var linearPrimary: LinearPrimaryButtonStyle { LinearPrimaryButtonStyle() }
    static func linearPrimary(color: Color) -> LinearPrimaryButtonStyle {
        LinearPrimaryButtonStyle(color: color)
    }
}

extension ButtonStyle where Self == LinearSecondaryButtonStyle {
    static var linearSecondary: LinearSecondaryButtonStyle { LinearSecondaryButtonStyle() }
    static func linearSecondary(color: Color) -> LinearSecondaryButtonStyle {
        LinearSecondaryButtonStyle(color: color)
    }
}

extension ButtonStyle where Self == LinearGhostButtonStyle {
    static var linearGhost: LinearGhostButtonStyle { LinearGhostButtonStyle() }
    static func linearGhost(color: Color) -> LinearGhostButtonStyle {
        LinearGhostButtonStyle(color: color)
    }
}

// MARK: - Linear TextField Style
// Dark-native text fields that fit Linear's aesthetic

struct LinearTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.inter(14))
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    .fill(Linear.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    .strokeBorder(Linear.border, lineWidth: 1)
            )
    }
}

extension TextFieldStyle where Self == LinearTextFieldStyle {
    static var linear: LinearTextFieldStyle { LinearTextFieldStyle() }
}

// MARK: - Linear Search Field Component

struct LinearSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Linear.textSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.inter(14))
                .foregroundColor(Linear.textPrimary)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Linear.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                .fill(Linear.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
        )
        .onHover { isHovered = $0 }
    }

    private var borderColor: Color {
        if isFocused { return Linear.borderFocus }
        if isHovered { return Linear.borderHover }
        return Linear.border
    }
}

// MARK: - Linear Row Components
// Dense list rows: 32-36px height, tight vertical, generous horizontal padding

/// Linear-style list row with hover state
struct LinearRow<Content: View>: View {
    let content: Content
    var isSelected: Bool = false
    @State private var isHovered = false

    init(isSelected: Bool = false, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, 6)      // Tight vertical (32-36px total height)
            .padding(.horizontal, 12)   // Generous horizontal
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .fill(backgroundColor)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }

    private var backgroundColor: Color {
        if isSelected { return Linear.selectedBackground }
        if isHovered { return Linear.hoverBackground }
        return Color.clear
    }
}

/// Linear-style sidebar row with icon, title, and optional count
struct LinearSidebarRow: View {
    let icon: String
    let title: String
    var count: Int? = nil
    var isSelected: Bool = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? Linear.textPrimary : Linear.textSecondary)
                .frame(width: 18)

            Text(title)
                .font(.inter(14))
                .foregroundColor(isSelected ? Linear.textPrimary : Linear.textPrimary)

            Spacer()

            if let count = count, count > 0 {
                Text("\(count)")
                    .font(.inter(12))
                    .foregroundColor(Linear.textSecondary)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                .fill(backgroundColor)
        )
        .padding(.horizontal, 8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected { return Linear.selectedBackground }
        if isHovered { return Linear.hoverBackground }
        return Color.clear
    }
}

/// Linear-style tab bar with matched geometry selection indicator
struct LinearTabBar: View {
    @Binding var selection: Int
    let tabs: [String]
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selection = index
                    }
                } label: {
                    Text(title)
                        .font(.inter(13, weight: selection == index ? .semibold : .regular))
                        .foregroundColor(selection == index ? Linear.textPrimary : Linear.textSecondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background {
                            if selection == index {
                                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                                    .fill(Linear.selectedBackground)
                                    .matchedGeometryEffect(id: "tab", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                .fill(Linear.surface)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct DesignTokensPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                // Colors
                Text("STATUS COLORS")
                    .sectionHeaderStyle()

                HStack(spacing: Spacing.medium) {
                    ForEach(FeatureStatus.allCases, id: \.self) { status in
                        VStack {
                            Circle()
                                .fill(StatusColor.color(for: status))
                                .frame(width: 40, height: 40)
                            Text(status.rawValue)
                                .font(Typography.caption)
                        }
                    }
                }

                // Typography
                Text("TYPOGRAPHY")
                    .sectionHeaderStyle()

                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text("Large Title").font(Typography.largeTitle)
                    Text("Section Header").font(Typography.sectionHeader)
                    Text("Feature Title").font(Typography.featureTitle)
                    Text("Body Text").font(Typography.body)
                    Text("Caption").font(Typography.caption)
                    Text("BADGE").font(Typography.badge)
                }

                // Spacing
                Text("SPACING")
                    .sectionHeaderStyle()

                HStack(spacing: Spacing.small) {
                    spacingBlock(Spacing.micro, "4")
                    spacingBlock(Spacing.small, "8")
                    spacingBlock(Spacing.medium, "12")
                    spacingBlock(Spacing.standard, "16")
                    spacingBlock(Spacing.large, "24")
                }
            }
            .padding(Spacing.large)
        }
        .frame(width: 500, height: 600)
    }

    func spacingBlock(_ size: CGFloat, _ label: String) -> some View {
        VStack {
            Rectangle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: size, height: size)
            Text(label)
                .font(Typography.caption)
        }
    }
}

#Preview {
    DesignTokensPreview()
}
#endif
