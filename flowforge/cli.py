"""
FlowForge CLI - AI-assisted parallel development orchestrator.

Commands:
    forge init              Initialize FlowForge in current directory
    forge add               Add a new feature
    forge list              List all features
    forge show <id>         Show feature details
    forge start <id>        Start working on a feature (create worktree + prompt)
    forge stop <id>         Mark feature as ready for review
    forge status            Show status of active features
    forge sync <id>         Sync feature branch with main
    forge merge-check       Check features ready for merge
    forge merge <id>        Merge a feature into main
"""

import typer
from rich.console import Console
from rich.table import Table
from rich.tree import Tree
from rich.panel import Panel
from rich.markdown import Markdown
from rich.prompt import Prompt, Confirm
from pathlib import Path
from typing import Optional
import json

from . import __version__
from .config import (
    FlowForgeConfig,
    ProjectConfig,
    find_project_root,
    detect_project_settings,
)
from .registry import Feature, FeatureRegistry, FeatureStatus, Complexity
from .worktree import WorktreeManager, ClaudeCodeLauncher
from .intelligence import IntelligenceEngine
from .prompt_builder import PromptBuilder
from .merge import MergeOrchestrator

app = typer.Typer(
    name="forge",
    help="FlowForge: AI-assisted parallel development orchestrator",
    no_args_is_help=True,
)
console = Console()


def get_context(require_init: bool = True) -> tuple[Path, FlowForgeConfig, FeatureRegistry]:
    """Get project context (root, config, registry)."""
    project_root = find_project_root()

    if require_init and not (project_root / ".flowforge").exists():
        console.print("[red]FlowForge not initialized. Run 'forge init' first.[/red]")
        raise typer.Exit(1)

    config = FlowForgeConfig.load(project_root) if require_init else None
    registry = FeatureRegistry.load(project_root) if require_init else None

    return project_root, config, registry


# ============================================================================
# Core Commands
# ============================================================================


@app.command()
def init(
    name: Optional[str] = typer.Option(None, "--name", "-n", help="Project name"),
    from_roadmap: Optional[Path] = typer.Option(
        None, "--from-roadmap", help="Import features from markdown files"
    ),
):
    """Initialize FlowForge in the current directory."""
    project_root = Path.cwd()

    if (project_root / ".flowforge").exists():
        if not Confirm.ask("FlowForge already initialized. Reinitialize?"):
            raise typer.Exit(0)

    console.print(f"\n🔨 Initializing FlowForge in [cyan]{project_root}[/cyan]\n")

    # Detect project settings
    detected = detect_project_settings(project_root)
    if name:
        detected.name = name

    # Create config
    config = FlowForgeConfig(project=detected)
    config.save(project_root)

    # Create registry
    registry = FeatureRegistry.create_new(project_root)

    # Create directory structure
    (project_root / ".flowforge" / "prompts").mkdir(parents=True, exist_ok=True)
    (project_root / ".flowforge" / "research").mkdir(parents=True, exist_ok=True)

    console.print(f"✅ Project: [green]{detected.name}[/green]")
    console.print(f"✅ Main branch: [green]{detected.main_branch}[/green]")
    console.print(f"✅ CLAUDE.md: [green]{detected.claude_md_path}[/green]")
    if detected.build_command:
        console.print(f"✅ Build command: [green]{detected.build_command}[/green]")

    # Import from roadmap if specified
    if from_roadmap:
        console.print(f"\n📥 Importing features from [cyan]{from_roadmap}[/cyan]...")
        count = import_features_from_roadmap(project_root, from_roadmap, registry)
        console.print(f"✅ Imported [green]{count}[/green] features")

    console.print("\n🎉 FlowForge initialized! Run [cyan]forge add[/cyan] to add features.")


@app.command()
def add(
    title: str = typer.Argument(..., help="Feature title"),
    description: Optional[str] = typer.Option(None, "--desc", "-d", help="Description"),
    parent: Optional[str] = typer.Option(None, "--parent", "-p", help="Parent feature ID"),
    spec: Optional[Path] = typer.Option(None, "--spec", "-s", help="Spec file path"),
    tags: Optional[str] = typer.Option(None, "--tags", "-t", help="Comma-separated tags"),
    complexity: Optional[str] = typer.Option(None, "--complexity", "-c", help="small/medium/large/epic"),
    priority: Optional[int] = typer.Option(None, "--priority", help="Priority (1=highest)"),
):
    """Add a new feature to the registry."""
    project_root, config, registry = get_context()

    # Generate ID from title
    feature_id = FeatureRegistry.generate_id(title)

    # Check for existing
    if registry.get_feature(feature_id):
        console.print(f"[red]Feature already exists: {feature_id}[/red]")
        raise typer.Exit(1)

    # Interactive prompts for missing info
    if not description:
        description = Prompt.ask("Description", default="")

    # Parse tags
    tag_list = [t.strip() for t in tags.split(",")] if tags else []

    # Parse complexity
    complexity_enum = Complexity.MEDIUM
    if complexity:
        try:
            complexity_enum = Complexity(complexity.lower())
        except ValueError:
            console.print(f"[yellow]Invalid complexity '{complexity}', using 'medium'[/yellow]")

    # Create feature
    feature = Feature(
        id=feature_id,
        title=title,
        description=description,
        parent_id=parent,
        spec_path=str(spec) if spec else None,
        tags=tag_list,
        complexity=complexity_enum,
        priority=priority or 5,
    )

    registry.add_feature(feature)

    console.print(f"\n✅ Added feature: [green]{feature_id}[/green]")
    console.print(f"   Title: {title}")
    console.print(f"   Status: {feature.status.value}")
    if parent:
        console.print(f"   Parent: {parent}")


@app.command("list")
def list_features(
    status_filter: Optional[str] = typer.Option(None, "--status", "-s", help="Filter by status"),
    tree_view: bool = typer.Option(True, "--tree/--flat", help="Show as tree or flat list"),
):
    """List all features."""
    project_root, config, registry = get_context()

    features = registry.list_features()

    if not features:
        console.print("[yellow]No features yet. Run 'forge add' to add one.[/yellow]")
        return

    if status_filter:
        try:
            status = FeatureStatus(status_filter)
            features = [f for f in features if f.status == status]
        except ValueError:
            console.print(f"[red]Invalid status: {status_filter}[/red]")
            raise typer.Exit(1)

    if tree_view:
        _show_feature_tree(features, registry)
    else:
        _show_feature_table(features)


def _show_feature_tree(features: list[Feature], registry: FeatureRegistry):
    """Display features as a tree."""
    tree = Tree("🔨 [bold]Features[/bold]")

    status_colors = {
        FeatureStatus.PLANNED: "white",
        FeatureStatus.IN_PROGRESS: "blue",
        FeatureStatus.REVIEW: "yellow",
        FeatureStatus.COMPLETED: "green",
        FeatureStatus.BLOCKED: "red",
    }

    def add_children(parent_tree, parent_id: Optional[str]):
        children = [f for f in features if f.parent_id == parent_id]
        for child in sorted(children, key=lambda f: f.priority):
            color = status_colors.get(child.status, "white")
            icon = "🔄" if child.worktree_path else "📋"
            branch = parent_tree.add(
                f"{icon} [{color}]{child.title}[/{color}] [dim]({child.id})[/dim] [{child.status.value}]"
            )
            add_children(branch, child.id)

    add_children(tree, None)
    console.print(tree)


def _show_feature_table(features: list[Feature]):
    """Display features as a table."""
    table = Table(title="Features")
    table.add_column("ID", style="cyan")
    table.add_column("Title")
    table.add_column("Status", style="magenta")
    table.add_column("Priority", justify="right")
    table.add_column("Worktree")

    for f in sorted(features, key=lambda f: (f.priority, f.title)):
        table.add_row(
            f.id,
            f.title[:40],
            f.status.value,
            str(f.priority),
            "✅" if f.worktree_path else "",
        )

    console.print(table)


@app.command()
def show(feature_id: str = typer.Argument(..., help="Feature ID")):
    """Show details for a specific feature."""
    project_root, config, registry = get_context()

    feature = registry.get_feature(feature_id)
    if not feature:
        console.print(f"[red]Feature not found: {feature_id}[/red]")
        raise typer.Exit(1)

    console.print(Panel(
        f"[bold]{feature.title}[/bold]\n\n"
        f"{feature.description or '(No description)'}\n\n"
        f"[dim]ID:[/dim] {feature.id}\n"
        f"[dim]Status:[/dim] {feature.status.value}\n"
        f"[dim]Priority:[/dim] {feature.priority}\n"
        f"[dim]Complexity:[/dim] {feature.complexity.value}\n"
        f"[dim]Tags:[/dim] {', '.join(feature.tags) or '(none)'}\n"
        f"[dim]Branch:[/dim] {feature.branch or '(none)'}\n"
        f"[dim]Worktree:[/dim] {feature.worktree_path or '(none)'}\n"
        f"[dim]Spec:[/dim] {feature.spec_path or '(none)'}\n"
        f"[dim]Created:[/dim] {feature.created_at}\n"
        f"[dim]Updated:[/dim] {feature.updated_at}",
        title=f"Feature: {feature_id}",
    ))


@app.command()
def start(
    feature_id: str = typer.Argument(..., help="Feature ID to start"),
    deep_research: bool = typer.Option(False, "--deep-research", "-r", help="Force deep research"),
    skip_experts: bool = typer.Option(False, "--skip-experts", help="Skip expert suggestion"),
    no_clipboard: bool = typer.Option(False, "--no-clipboard", help="Don't copy prompt to clipboard"),
):
    """
    Start working on a feature.

    Creates a git worktree, generates an implementation prompt with
    expert consultation, and prepares Claude Code launch instructions.
    """
    project_root, config, registry = get_context()

    feature = registry.get_feature(feature_id)
    if not feature:
        console.print(f"[red]Feature not found: {feature_id}[/red]")
        raise typer.Exit(1)

    if feature.status == FeatureStatus.COMPLETED:
        console.print(f"[yellow]Feature is already completed.[/yellow]")
        raise typer.Exit(1)

    console.print(f"\n🚀 Starting feature: [cyan]{feature.title}[/cyan]\n")

    # Initialize managers
    worktree_mgr = WorktreeManager(project_root, config.project.worktree_base)
    intelligence = IntelligenceEngine(project_root)
    prompt_builder = PromptBuilder(project_root, registry, intelligence)

    # Step 1: Check if deep research is needed
    if not deep_research and not skip_experts:
        console.print("🔍 Analyzing feature complexity...")
        recommendation = intelligence.analyze_research_need(
            feature.title,
            feature.description,
            feature.tags,
        )

        if recommendation.should_research:
            console.print(f"\n[yellow]💡 Deep research recommended:[/yellow]")
            console.print(f"   {recommendation.reasoning}")
            console.print(f"   Topics: {', '.join(recommendation.topics)}")

            if Confirm.ask("\nLaunch deep research threads?"):
                prompts = intelligence.generate_research_prompts(
                    feature.title,
                    feature.description,
                    recommendation.topics,
                    recommendation.providers,
                )

                console.print("\n📚 Opening research sessions...")
                for provider in prompts:
                    console.print(f"   • {provider}")

                intelligence.open_research_sessions(feature_id, prompts)

                console.print("\n[yellow]Complete your research, then run:[/yellow]")
                console.print(f"   forge start {feature_id} --skip-experts")
                console.print("\n(Research will be synthesized into the implementation prompt)")
                return

    # Step 2: Create worktree
    worktree_path = worktree_mgr.get_worktree_path(feature_id)
    if not worktree_path:
        console.print("📁 Creating worktree...")
        try:
            worktree_path = worktree_mgr.create_for_feature(
                feature_id,
                config.project.main_branch,
            )
            console.print(f"   ✅ Created: [green]{worktree_path}[/green]")
        except Exception as e:
            console.print(f"   [red]Failed to create worktree: {e}[/red]")
            raise typer.Exit(1)
    else:
        console.print(f"📁 Using existing worktree: [green]{worktree_path}[/green]")

    # Step 3: Generate prompt
    console.print("📝 Generating implementation prompt...")

    # Get expert suggestions if not skipped
    if not skip_experts:
        console.print("   🧠 Consulting experts...")
        experts = intelligence.suggest_experts(
            feature.title,
            feature.description,
            feature.tags,
        )
        if experts:
            console.print("   Suggested experts:")
            for e in experts:
                console.print(f"      • {e.name} ({e.title})")

    prompt = prompt_builder.build_for_feature(
        feature_id,
        config.project.claude_md_path,
        include_experts=not skip_experts,
        include_research=True,
    )

    # Save prompt
    prompt_path = prompt_builder.save_prompt(feature_id, prompt)
    console.print(f"   ✅ Saved: [green]{prompt_path}[/green]")

    # Copy to clipboard
    if not no_clipboard:
        try:
            import pyperclip
            pyperclip.copy(prompt)
            console.print("   ✅ Copied to clipboard")
        except Exception:
            console.print("   [yellow]Could not copy to clipboard[/yellow]")

    # Step 4: Update registry
    registry.update_feature(
        feature_id,
        status=FeatureStatus.IN_PROGRESS,
        branch=f"feature/{feature_id}",
        worktree_path=str(worktree_path),
        prompt_path=str(prompt_path),
    )

    # Step 5: Show launch instructions
    launcher = ClaudeCodeLauncher(
        config.project.claude_command,
        config.project.claude_flags,
    )

    console.print("\n" + "=" * 60)
    console.print("\n[bold green]Ready to implement![/bold green]\n")
    console.print("Launch Claude Code with:\n")
    console.print(f"  [cyan]cd {worktree_path}[/cyan]")
    console.print(f"  [cyan]{config.project.claude_command} {' '.join(config.project.claude_flags)}[/cyan]")
    console.print("\nThen paste the prompt from your clipboard.\n")
    console.print("=" * 60)


@app.command()
def stop(
    feature_id: str = typer.Argument(..., help="Feature ID to stop"),
):
    """Mark a feature as ready for review."""
    project_root, config, registry = get_context()

    feature = registry.get_feature(feature_id)
    if not feature:
        console.print(f"[red]Feature not found: {feature_id}[/red]")
        raise typer.Exit(1)

    registry.update_feature(feature_id, status=FeatureStatus.REVIEW)

    console.print(f"\n✅ Feature [cyan]{feature_id}[/cyan] marked as ready for review.")
    console.print(f"\nNext steps:")
    console.print(f"  • forge merge-check {feature_id}  - Check for conflicts")
    console.print(f"  • forge merge {feature_id}        - Merge into main")


@app.command()
def status():
    """Show status of all active features and worktrees."""
    project_root, config, registry = get_context()
    worktree_mgr = WorktreeManager(project_root, config.project.worktree_base)

    stats = registry.get_stats()

    console.print(Panel(
        f"[bold]Project:[/bold] {config.project.name}\n"
        f"[bold]Total features:[/bold] {stats['total']}\n\n"
        f"  📋 Planned: {stats['by_status'].get('planned', 0)}\n"
        f"  🔄 In Progress: {stats['by_status'].get('in-progress', 0)}\n"
        f"  👀 Review: {stats['by_status'].get('review', 0)}\n"
        f"  ✅ Completed: {stats['by_status'].get('completed', 0)}\n"
        f"  🚫 Blocked: {stats['by_status'].get('blocked', 0)}\n\n"
        f"[bold]Active worktrees:[/bold] {stats['active_worktrees']}\n"
        f"[bold]Ready to merge:[/bold] {stats['ready_to_merge']}",
        title="FlowForge Status",
    ))

    # Show active worktrees
    active = [f for f in registry.list_features() if f.worktree_path]
    if active:
        console.print("\n[bold]Active Worktrees:[/bold]\n")
        table = Table()
        table.add_column("Feature")
        table.add_column("Status")
        table.add_column("Commits")
        table.add_column("Changes")

        for f in active:
            wt_status = worktree_mgr.get_status(f.id)
            table.add_row(
                f.title[:30],
                f.status.value,
                str(wt_status.ahead_of_main) if wt_status.exists else "-",
                "Yes" if wt_status.has_changes else "No",
            )

        console.print(table)


@app.command()
def version():
    """Show FlowForge version."""
    console.print(f"FlowForge v{__version__}")


# ============================================================================
# Merge Commands
# ============================================================================


@app.command()
def sync(
    feature_id: str = typer.Argument(..., help="Feature ID to sync"),
):
    """
    Sync a feature branch with latest main (rebase).

    This updates your feature branch to include the latest changes from main,
    keeping your commits on top. Run this regularly to avoid merge conflicts.
    """
    project_root, config, registry = get_context()

    feature = registry.get_feature(feature_id)
    if not feature:
        console.print(f"[red]Feature not found: {feature_id}[/red]")
        raise typer.Exit(1)

    if not feature.worktree_path:
        console.print(f"[red]Feature has no worktree. Run 'forge start {feature_id}' first.[/red]")
        raise typer.Exit(1)

    console.print(f"\n🔄 Syncing [cyan]{feature.title}[/cyan] with {config.project.main_branch}...\n")

    orchestrator = MergeOrchestrator(
        project_root,
        registry,
        config.project.main_branch,
        config.project.build_command,
    )

    success, message = orchestrator.sync_feature(feature_id)

    if success:
        console.print(f"[green]✅ {message}[/green]")
    else:
        console.print(f"[red]❌ {message}[/red]")
        raise typer.Exit(1)


@app.command("merge-check")
def merge_check(
    feature_id: Optional[str] = typer.Argument(None, help="Feature ID (optional, checks all if omitted)"),
):
    """
    Check if features are ready to merge (dry-run conflict detection).

    Without an ID, checks all features in 'review' status and shows
    the recommended merge order based on dependencies.
    """
    project_root, config, registry = get_context()

    orchestrator = MergeOrchestrator(
        project_root,
        registry,
        config.project.main_branch,
        config.project.build_command,
    )

    if feature_id:
        # Check specific feature
        feature = registry.get_feature(feature_id)
        if not feature:
            console.print(f"[red]Feature not found: {feature_id}[/red]")
            raise typer.Exit(1)

        console.print(f"\n🔍 Checking merge conflicts for [cyan]{feature.title}[/cyan]...\n")

        result = orchestrator.check_conflicts(feature_id)

        if result.success:
            console.print(f"[green]✅ No conflicts detected. Ready to merge![/green]")
        else:
            console.print(f"[red]❌ {result.message}[/red]")
            if result.conflict_files:
                console.print("\n[yellow]Conflicting files:[/yellow]")
                for f in result.conflict_files:
                    console.print(f"   • {f}")
                console.print(f"\n[dim]Run 'forge sync {feature_id}' to resolve conflicts[/dim]")
            raise typer.Exit(1)
    else:
        # Check all features in review status
        review_features = registry.list_features(status=FeatureStatus.REVIEW)

        if not review_features:
            console.print("[yellow]No features in review status.[/yellow]")
            return

        console.print(f"\n🔍 Checking {len(review_features)} feature(s) in review...\n")

        # Compute merge order
        merge_order = orchestrator.compute_merge_order()

        if not merge_order:
            console.print("[yellow]No features ready to merge.[/yellow]")
            return

        console.print("[bold]Recommended merge order:[/bold]\n")

        table = Table()
        table.add_column("#", style="dim")
        table.add_column("Feature")
        table.add_column("Conflicts")
        table.add_column("Status")

        for i, fid in enumerate(merge_order, 1):
            feature = registry.get_feature(fid)
            result = orchestrator.check_conflicts(fid)

            if result.success:
                conflict_status = "[green]None[/green]"
                ready = "[green]✓ Ready[/green]"
            else:
                conflict_status = f"[red]{len(result.conflict_files)} file(s)[/red]"
                ready = "[red]✗ Needs sync[/red]"

            table.add_row(str(i), feature.title[:40], conflict_status, ready)

        console.print(table)

        # Show summary
        ready_count = sum(
            1 for fid in merge_order
            if orchestrator.check_conflicts(fid).success
        )
        console.print(f"\n[bold]{ready_count}/{len(merge_order)}[/bold] features ready to merge.")

        if ready_count > 0:
            console.print("\nRun [cyan]forge merge <id>[/cyan] to merge a feature, or")
            console.print("[cyan]forge merge --auto[/cyan] to merge all safe features in order.")


@app.command()
def merge(
    feature_id: Optional[str] = typer.Argument(None, help="Feature ID to merge"),
    auto: bool = typer.Option(False, "--auto", "-a", help="Merge all safe features in order"),
    no_validate: bool = typer.Option(False, "--no-validate", help="Skip build validation"),
    keep_worktree: bool = typer.Option(False, "--keep", "-k", help="Keep worktree after merge"),
):
    """
    Merge a feature into main.

    Performs a pre-flight conflict check, merges the feature branch,
    runs build validation (if configured), and cleans up the worktree.

    Use --auto to merge all conflict-free features in dependency order.
    """
    project_root, config, registry = get_context()

    orchestrator = MergeOrchestrator(
        project_root,
        registry,
        config.project.main_branch,
        config.project.build_command,
    )

    if auto:
        # Merge all safe features
        console.print("\n🚀 Auto-merging all safe features...\n")

        results = orchestrator.merge_all_safe(validate=not no_validate)

        if not results:
            console.print("[yellow]No features to merge.[/yellow]")
            return

        # Show results
        success_count = sum(1 for r in results if r.success)
        console.print(f"\n[bold]Merge Results:[/bold]\n")

        for result in results:
            feature = registry.get_feature(result.feature_id)
            title = feature.title if feature else result.feature_id

            if result.success:
                console.print(f"  [green]✓[/green] {title}")
            else:
                console.print(f"  [red]✗[/red] {title}: {result.message}")
                if result.conflict_files:
                    for f in result.conflict_files:
                        console.print(f"      • {f}")

        console.print(f"\n[bold]{success_count}/{len(results)}[/bold] features merged successfully.")

        if success_count < len(results):
            console.print("\n[yellow]Some merges failed. Resolve conflicts and try again.[/yellow]")
            raise typer.Exit(1)
    else:
        # Merge specific feature
        if not feature_id:
            console.print("[red]Feature ID required. Use --auto to merge all.[/red]")
            raise typer.Exit(1)

        feature = registry.get_feature(feature_id)
        if not feature:
            console.print(f"[red]Feature not found: {feature_id}[/red]")
            raise typer.Exit(1)

        console.print(f"\n🔀 Merging [cyan]{feature.title}[/cyan] into {config.project.main_branch}...\n")

        # Confirm merge
        if not typer.confirm(f"Merge '{feature.title}' into {config.project.main_branch}?"):
            console.print("[yellow]Merge cancelled.[/yellow]")
            raise typer.Exit(0)

        result = orchestrator.merge_feature(
            feature_id,
            validate=not no_validate,
            auto_cleanup=not keep_worktree,
        )

        if result.success:
            console.print(f"\n[green]✅ {result.message}[/green]")

            if not keep_worktree:
                console.print(f"[dim]Worktree and branch cleaned up.[/dim]")
            else:
                console.print(f"[dim]Worktree preserved at: {feature.worktree_path}[/dim]")

            console.print(f"\n🎉 Feature complete!")
        else:
            console.print(f"\n[red]❌ {result.message}[/red]")

            if result.conflict_files:
                console.print("\n[yellow]Conflicting files:[/yellow]")
                for f in result.conflict_files:
                    console.print(f"   • {f}")

                # Offer to generate conflict resolution prompt
                if typer.confirm("\nGenerate conflict resolution prompt for Claude Code?"):
                    prompt = orchestrator.generate_conflict_prompt(feature_id)
                    try:
                        import pyperclip
                        pyperclip.copy(prompt)
                        console.print("\n[green]✅ Resolution prompt copied to clipboard![/green]")
                    except Exception:
                        console.print("\n[bold]Conflict Resolution Prompt:[/bold]\n")
                        console.print(Markdown(prompt))

            if result.validation_output:
                console.print("\n[yellow]Validation output:[/yellow]")
                console.print(result.validation_output)

            raise typer.Exit(1)


# ============================================================================
# Helper Functions
# ============================================================================


def import_features_from_roadmap(
    project_root: Path,
    roadmap_path: Path,
    registry: FeatureRegistry,
) -> int:
    """Import features from markdown files in a roadmap directory."""
    count = 0

    roadmap_dir = project_root / roadmap_path
    if not roadmap_dir.exists():
        return 0

    for md_file in roadmap_dir.glob("**/*.md"):
        # Parse markdown file for feature info
        content = md_file.read_text()
        lines = content.split("\n")

        # First heading is the title
        title = None
        for line in lines:
            if line.startswith("# "):
                title = line[2:].strip()
                break

        if not title:
            title = md_file.stem.replace("-", " ").replace("_", " ").title()

        # Generate ID
        feature_id = FeatureRegistry.generate_id(title)

        # Skip if already exists
        if registry.get_feature(feature_id):
            continue

        # Extract description (first paragraph after title)
        description = ""
        in_description = False
        for line in lines:
            if line.startswith("# "):
                in_description = True
                continue
            if in_description:
                if line.startswith("#"):
                    break
                if line.strip():
                    description += line + " "

        description = description.strip()[:500]

        # Create feature
        feature = Feature(
            id=feature_id,
            title=title,
            description=description,
            spec_path=str(md_file.relative_to(project_root)),
        )

        registry.add_feature(feature)
        count += 1

    return count


if __name__ == "__main__":
    app()
