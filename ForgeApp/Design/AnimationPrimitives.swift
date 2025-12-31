import SwiftUI

// MARK: - Animation Primitives
// Influenced by: Mike Matas (physics, fluid), Bret Victor (immediate), Jony Ive (considered)
//
// "The best interface is one that doesn't feel like an interface at all." — Mike Matas
// Every animation has weight, momentum, and personality.

// MARK: - Spring Configurations
// Physics-based springs with configurable tension/damping

enum SpringPreset {
    /// Snappy response for micro-interactions (buttons, hovers)
    /// Quick attack, minimal overshoot
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.8, blendDuration: 0)

    /// Bouncy for delightful moments (card drops, celebrations)
    /// Playful overshoot, settles naturally
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)

    /// Smooth for state transitions (color changes, layout shifts)
    /// No overshoot, elegant easing
    static let smooth = Animation.spring(response: 0.35, dampingFraction: 1.0, blendDuration: 0)

    /// Gentle for large movements (modal appear, graph zoom)
    /// Slower, more dramatic
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0)

    /// Celebration spring (confetti, streak level-up)
    /// Maximum bounce, joyful
    static let celebration = Animation.spring(response: 0.6, dampingFraction: 0.5, blendDuration: 0)
}

// MARK: - Timing Curves
// For when springs aren't appropriate

enum TimingCurve {
    /// Ease out — fast start, slow finish (natural deceleration)
    static let easeOut = Animation.easeOut(duration: Timing.standard)

    /// Ease in out — smooth acceleration and deceleration
    static let easeInOut = Animation.easeInOut(duration: Timing.standard)

    /// Linear — constant speed (progress bars, loaders)
    static let linear = Animation.linear(duration: Timing.standard)

    /// Quick ease out — for micro-interactions
    static let quickEaseOut = Animation.easeOut(duration: Timing.micro)
}

// MARK: - Linear Timing
// Exact values from Linear's CTO: hover transitions use exactly 150ms
// Any deviation is treated as a quality defect
//
// | Interaction      | Duration | Curve/Spring                              |
// |------------------|----------|-------------------------------------------|
// | Hover in/out     | 150ms    | .easeInOut(duration: 0.15)                |
// | Button press     | 120ms    | .snappy(duration: 0.12)                   |
// | Selection change | 200ms    | .snappy(duration: 0.2)                    |
// | View transitions | 300-400ms| .spring(response: 0.35, dampingFraction: 0.85) |
// | Modal present    | 350ms    | .spring(response: 0.35, dampingFraction: 0.9)  |

enum LinearTiming {
    /// Hover in/out — 150ms (THE GOLDEN VALUE)
    static let hover: Double = 0.15

    /// Button press — 120ms
    static let press: Double = 0.12

    /// Selection change — 200ms
    static let selection: Double = 0.2

    /// View transitions — 350ms
    static let transition: Double = 0.35

    /// Modal presentation — 350ms
    static let modal: Double = 0.35

    // Legacy aliases
    static var fast: Double { hover }
    static var standard: Double { selection }
    static var slow: Double { transition }
}

enum LinearEasing {
    /// Hover — easeInOut at 150ms (not easeOut!)
    static let hover = Animation.easeInOut(duration: LinearTiming.hover)

    /// Button press — snappy spring at 120ms
    static let press = Animation.snappy(duration: LinearTiming.press)

    /// Selection — snappy spring at 200ms
    static let selection = Animation.snappy(duration: LinearTiming.selection)

    /// View transition — spring with 0.85 damping
    static let transition = Animation.spring(response: LinearTiming.transition, dampingFraction: 0.85)

    /// Modal — spring with 0.9 damping (less bounce)
    static let modal = Animation.spring(response: LinearTiming.modal, dampingFraction: 0.9)

    // Legacy aliases
    static var fast: Animation { hover }
    static var standard: Animation { selection }
    static var slow: Animation { transition }
}

// MARK: - Interactive Animation Modifiers

extension View {
    /// Button press effect — Matas-style tactile feedback
    /// Scale down slightly, reduce shadow
    func pressable(isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(SpringPreset.snappy, value: isPressed)
    }

    /// Hover effect — subtle elevation increase
    func hoverable(isHovered: Bool) -> some View {
        self
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(
                color: .black.opacity(isHovered ? 0.15 : 0.05),
                radius: isHovered ? 8 : 2,
                y: isHovered ? 4 : 1
            )
            .animation(SpringPreset.snappy, value: isHovered)
    }

    /// Linear-style hover — background color shift instead of scale
    /// Uses exact 150ms easeInOut timing
    func linearHover(isHovered: Bool, hoverColor: Color = Linear.hoverBackground, radius: CGFloat = CornerRadius.medium) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isHovered ? hoverColor : Color.clear)
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    /// Card drag effect — physics-based with rotation hint
    func draggable(offset: CGSize, isDragging: Bool) -> some View {
        self
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width) / 20), anchor: .center)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .shadow(
                color: .black.opacity(isDragging ? 0.2 : 0.1),
                radius: isDragging ? 12 : 4,
                y: isDragging ? 8 : 2
            )
            .animation(SpringPreset.bouncy, value: isDragging)
    }

    /// Shimmer effect for loading states
    func shimmer(isActive: Bool) -> some View {
        self.modifier(ShimmerModifier(isActive: isActive))
    }

    /// Pulse effect for attention
    func pulse(isActive: Bool) -> some View {
        self.modifier(PulseModifier(isActive: isActive))
    }

    /// Bounce in animation for appearing elements
    func bounceIn(isVisible: Bool, delay: Double = 0) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.5)
            .animation(
                SpringPreset.bouncy.delay(delay),
                value: isVisible
            )
    }

    /// Slide in from edge
    func slideIn(from edge: Edge, isVisible: Bool, delay: Double = 0) -> some View {
        let offset: CGSize = {
            switch edge {
            case .top: return CGSize(width: 0, height: -50)
            case .bottom: return CGSize(width: 0, height: 50)
            case .leading: return CGSize(width: -50, height: 0)
            case .trailing: return CGSize(width: 50, height: 0)
            }
        }()

        return self
            .opacity(isVisible ? 1 : 0)
            .offset(isVisible ? .zero : offset)
            .animation(
                SpringPreset.smooth.delay(delay),
                value: isVisible
            )
    }
}

// MARK: - Custom View Modifiers

/// Shimmer loading effect
struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    if isActive {
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.4),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 2)
                        .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
                        .animation(
                            Animation.linear(duration: 1.5).repeatForever(autoreverses: false),
                            value: phase
                        )
                    }
                }
            )
            .clipped()
            .onAppear {
                if isActive {
                    phase = 1
                }
            }
    }
}

/// Pulse attention effect
struct PulseModifier: ViewModifier {
    let isActive: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing && isActive ? 1.05 : 1.0)
            .opacity(isPulsing && isActive ? 0.8 : 1.0)
            .animation(
                isActive ?
                    Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) :
                    .default,
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Transition Presets
// Matas-style fluid transitions

extension AnyTransition {
    /// Scale + fade for appearing elements
    static var scaleAndFade: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 1.1).combined(with: .opacity)
        )
    }

    /// Slide up from bottom with fade
    static var slideUp: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }

    /// Blur transition for modals
    static var blur: AnyTransition {
        .modifier(
            active: BlurModifier(radius: 10, opacity: 0),
            identity: BlurModifier(radius: 0, opacity: 1)
        )
    }
}

struct BlurModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
    }
}

// MARK: - Gesture Velocity Helpers
// For velocity-aware animations (fast swipe = fast result)

struct VelocityTracker {
    var lastPosition: CGPoint = .zero
    var lastTime: Date = Date()
    var velocity: CGPoint = .zero

    mutating func update(position: CGPoint) {
        let now = Date()
        let dt = now.timeIntervalSince(lastTime)

        if dt > 0 {
            velocity = CGPoint(
                x: (position.x - lastPosition.x) / dt,
                y: (position.y - lastPosition.y) / dt
            )
        }

        lastPosition = position
        lastTime = now
    }

    /// Get animation duration based on velocity (faster swipe = shorter duration)
    func animationDuration(base: Double = 0.3, minDuration: Double = 0.1) -> Double {
        let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        let factor = min(1.0, speed / 1000) // Normalize to reasonable range
        return max(minDuration, base * (1 - factor * 0.7))
    }
}

// MARK: - Number Animation
// For streak counters, progress values

struct AnimatedNumber: View {
    let value: Int
    let font: Font

    @State private var displayValue: Int = 0

    var body: some View {
        Text("\(displayValue)")
            .font(font)
            .contentTransition(.numericText(value: Double(displayValue)))
            .onChange(of: value) { oldValue, newValue in
                withAnimation(SpringPreset.bouncy) {
                    displayValue = newValue
                }
            }
            .onAppear {
                displayValue = value
            }
    }
}

// MARK: - Progress Ring Animation

struct AnimatedProgressRing: View {
    let progress: Double // 0.0 to 1.0
    let lineWidth: CGFloat
    let color: Color

    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(SpringPreset.smooth, value: animatedProgress)
        }
        .onChange(of: progress) { _, newValue in
            animatedProgress = newValue
        }
        .onAppear {
            // Animate in on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                animatedProgress = progress
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AnimationPrimitivesPreview: View {
    @State private var isPressed = false
    @State private var isHovered = false
    @State private var showCard = false
    @State private var progress: Double = 0

    var body: some View {
        VStack(spacing: Spacing.large) {
            Text("ANIMATION PRIMITIVES")
                .sectionHeaderStyle()

            // Press effect
            Button("Press Me") {
                // Action
            }
            .padding()
            .background(Accent.primary)
            .foregroundColor(.white)
            .cornerRadius(CornerRadius.medium)
            .pressable(isPressed: isPressed)
            .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})

            // Hover effect
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .fill(Surface.elevated)
                .frame(height: 100)
                .overlay(Text("Hover Me"))
                .hoverable(isHovered: isHovered)
                .onHover { isHovered = $0 }

            // Bounce in
            HStack {
                Button("Toggle Card") {
                    showCard.toggle()
                }

                if showCard {
                    Text("I bounced in!")
                        .padding()
                        .background(Accent.success.opacity(0.2))
                        .cornerRadius(CornerRadius.medium)
                        .bounceIn(isVisible: showCard)
                }
            }

            // Progress ring
            VStack {
                AnimatedProgressRing(
                    progress: progress,
                    lineWidth: 8,
                    color: Accent.primary
                )
                .frame(width: 60, height: 60)

                Button("Animate Progress") {
                    progress = progress < 0.5 ? 1.0 : 0.0
                }
            }

            // Animated number
            AnimatedNumber(value: Int(progress * 100), font: Typography.streakNumber)
        }
        .padding(Spacing.large)
        .frame(width: 400, height: 500)
    }
}

#Preview {
    AnimationPrimitivesPreview()
}
#endif
