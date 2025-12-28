import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Sheet for managing deep research for a feature.
///
/// Allows users to:
/// - View/export research prompts for various providers
/// - Drag & drop research reports (markdown files)
/// - View and synthesize uploaded reports
struct ResearchSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let project: String
    let featureId: String
    let featureTitle: String

    private let apiClient = APIClient()

    @State private var prompts: ResearchPrompts?
    @State private var reports: ResearchReportList?
    @State private var isLoadingPrompts = false
    @State private var isLoadingReports = false
    @State private var isSynthesizing = false
    @State private var isSavingPrompts = false
    @State private var errorMessage: String?

    // Drop zone
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    // Research prompts section
                    promptsSection

                    Divider()
                        .padding(.vertical, Spacing.medium)

                    // Reports section
                    reportsSection

                    // Synthesis section
                    if let reports = reports, reports.reportCount > 0 {
                        Divider()
                            .padding(.vertical, Spacing.medium)
                        synthesisSection
                    }
                }
                .padding(Spacing.large)
            }
        }
        .frame(minWidth: 550, idealWidth: 650, minHeight: 500, idealHeight: 650)
        .onAppear {
            loadData()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.micro) {
                Label("Deep Research", systemImage: "brain.head.profile")
                    .font(Typography.caption)
                    .foregroundColor(Accent.primary)

                Text(featureTitle)
                    .font(Typography.sectionHeader)
                    .lineLimit(1)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.escape)
        }
        .padding(Spacing.standard)
    }

    // MARK: - Prompts Section

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack {
                Text("Research Prompts")
                    .sectionHeaderStyle()

                Spacer()

                if let prompts = prompts {
                    Button(action: savePromptsToDesktop) {
                        if isSavingPrompts {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Label("Save to Desktop", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSavingPrompts)
                }
            }

            if isLoadingPrompts {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating prompts...")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            } else if let prompts = prompts {
                Text("Copy these prompts to use in your preferred research tool:")
                    .font(Typography.caption)
                    .foregroundColor(.secondary)

                VStack(spacing: Spacing.small) {
                    ForEach(Array(prompts.prompts.keys.sorted()), id: \.self) { provider in
                        promptRow(provider: provider, prompt: prompts.prompts[provider] ?? "")
                    }
                }

                if !prompts.topics.isEmpty {
                    HStack(spacing: Spacing.small) {
                        Text("Topics:")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                        Text(prompts.topics.joined(separator: ", "))
                            .font(Typography.caption)
                    }
                    .padding(.top, Spacing.small)
                }
            }
        }
    }

    private func promptRow(provider: String, prompt: String) -> some View {
        HStack {
            Image(systemName: iconForProvider(provider))
                .foregroundColor(colorForProvider(provider))
                .frame(width: 24)

            Text(displayNameForProvider(provider))
                .font(Typography.body)

            Spacer()

            Button(action: {
                PlatformPasteboard.copy(prompt)
            }) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
        .padding(Spacing.medium)
        .background(Surface.elevated)
        .cornerRadius(CornerRadius.medium)
    }

    // MARK: - Reports Section

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Research Reports")
                .sectionHeaderStyle()

            // Drop zone
            dropZone

            // Existing reports
            if let reports = reports, !reports.reports.isEmpty {
                VStack(spacing: Spacing.small) {
                    ForEach(reports.reports) { report in
                        reportRow(report)
                    }
                }
            } else if !isLoadingReports {
                Text("No reports uploaded yet. Drag markdown files here or use the file picker.")
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: Spacing.medium) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 32))
                .foregroundColor(isDropTargeted ? Accent.primary : .secondary)

            Text("Drop .md files here")
                .font(Typography.body)
                .foregroundColor(isDropTargeted ? Accent.primary : .secondary)

            #if os(macOS)
            Button("Browse...") {
                openFilePicker()
            }
            .buttonStyle(.bordered)
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .strokeBorder(
                    isDropTargeted ? Accent.primary : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
        )
        .background(
            isDropTargeted ? Accent.primary.opacity(0.05) : Color.clear
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private func reportRow(_ report: ResearchReport) -> some View {
        HStack {
            Image(systemName: iconForProvider(report.provider))
                .foregroundColor(colorForProvider(report.provider))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayNameForProvider(report.provider))
                    .font(Typography.body)

                Text(report.preview)
                    .font(Typography.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: {
                deleteReport(provider: report.provider)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.medium)
        .background(Surface.elevated)
        .cornerRadius(CornerRadius.medium)
    }

    // MARK: - Synthesis Section

    private var synthesisSection: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack {
                Text("Synthesis")
                    .sectionHeaderStyle()

                Spacer()

                Button(action: synthesize) {
                    if isSynthesizing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Synthesize", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSynthesizing || (reports?.reportCount ?? 0) == 0)
            }

            if let reports = reports {
                if reports.hasSynthesis, let preview = reports.synthesisPreview {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Accent.success)
                            Text("Synthesis ready")
                                .font(Typography.caption)
                                .fontWeight(.medium)
                                .foregroundColor(Accent.success)
                        }

                        Text(preview)
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                            .padding(Spacing.medium)
                            .background(Surface.elevated)
                            .cornerRadius(CornerRadius.medium)

                        Text("This synthesis will be included in your build prompt.")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                } else {
                    Text("Click 'Synthesize' to combine research reports into unified implementation context.")
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        Task {
            await loadPrompts()
            await loadReports()
        }
    }

    private func loadPrompts() async {
        isLoadingPrompts = true
        defer { isLoadingPrompts = false }

        do {
            prompts = try await apiClient.getResearchPrompts(project: project, featureId: featureId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadReports() async {
        isLoadingReports = true
        defer { isLoadingReports = false }

        do {
            reports = try await apiClient.getResearchReports(project: project, featureId: featureId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func savePromptsToDesktop() {
        guard let prompts = prompts else { return }
        isSavingPrompts = true

        Task {
            defer {
                Task { @MainActor in
                    isSavingPrompts = false
                }
            }

            // Build prompts file content
            var content = "# Research Prompts for: \(featureTitle)\n\n"
            content += "Topics: \(prompts.topics.joined(separator: ", "))\n\n"
            content += "---\n\n"

            for provider in prompts.prompts.keys.sorted() {
                if let prompt = prompts.prompts[provider] {
                    content += "## \(displayNameForProvider(provider))\n\n"
                    content += prompt + "\n\n"
                    content += "---\n\n"
                }
            }

            // Save to Desktop
            let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            let sanitizedTitle = featureTitle.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "-", options: .regularExpression)
            let filename = "FlowForge-Research-\(sanitizedTitle).md"
            let fileURL = desktopURL.appendingPathComponent(filename)

            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                #endif
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                // Check if it's a markdown file
                guard url.pathExtension.lowercased() == "md" else {
                    return
                }

                // Read and upload
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let provider = inferProviderFromFilename(url.lastPathComponent)
                    uploadResearchReport(provider: provider, content: content)
                } catch {
                    Task { @MainActor in
                        errorMessage = "Failed to read file: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    #if os(macOS)
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md")!]

        if panel.runModal() == .OK {
            for url in panel.urls {
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let provider = inferProviderFromFilename(url.lastPathComponent)
                    uploadResearchReport(provider: provider, content: content)
                } catch {
                    errorMessage = "Failed to read file: \(error.localizedDescription)"
                }
            }
        }
    }
    #endif

    private func inferProviderFromFilename(_ filename: String) -> String {
        let lower = filename.lowercased()
        if lower.contains("openevidence") { return "openevidence" }
        if lower.contains("gemini") { return "gemini" }
        if lower.contains("chatgpt") || lower.contains("gpt") { return "chatgpt" }
        if lower.contains("claude") { return "claude" }
        if lower.contains("perplexity") { return "perplexity" }
        return "research"  // Generic fallback
    }

    private func uploadResearchReport(provider: String, content: String) {
        Task {
            do {
                try await apiClient.uploadResearch(
                    project: project,
                    featureId: featureId,
                    provider: provider,
                    content: content
                )
                await loadReports()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteReport(provider: String) {
        Task {
            do {
                try await apiClient.deleteResearch(
                    project: project,
                    featureId: featureId,
                    provider: provider
                )
                await loadReports()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func synthesize() {
        isSynthesizing = true

        Task {
            defer {
                Task { @MainActor in
                    isSynthesizing = false
                }
            }

            do {
                _ = try await apiClient.synthesizeResearch(project: project, featureId: featureId)
                await loadReports()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func iconForProvider(_ provider: String) -> String {
        switch provider.lowercased() {
        case "claude": return "brain"
        case "gemini": return "sparkles"
        case "chatgpt", "gpt": return "bubble.left.and.bubble.right"
        case "openevidence": return "stethoscope"
        case "perplexity": return "magnifyingglass"
        default: return "doc.text"
        }
    }

    private func colorForProvider(_ provider: String) -> Color {
        switch provider.lowercased() {
        case "claude": return Color.orange
        case "gemini": return Color.blue
        case "chatgpt", "gpt": return Color.green
        case "openevidence": return Color.red
        case "perplexity": return Color.purple
        default: return Color.secondary
        }
    }

    private func displayNameForProvider(_ provider: String) -> String {
        switch provider.lowercased() {
        case "claude": return "Claude"
        case "gemini": return "Gemini"
        case "chatgpt", "gpt": return "ChatGPT"
        case "openevidence": return "OpenEvidence"
        case "perplexity": return "Perplexity"
        default: return provider.capitalized
        }
    }
}
