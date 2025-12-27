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
from .github_health import GitHubHealthChecker, HealthStatus
from .config import (
    FlowForgeConfig,
    ProjectConfig,
    find_project_root,
    detect_project_settings,
)
from .registry import Feature, FeatureRegistry, FeatureStatus, Complexity
from .worktree import WorktreeManager, ClaudeCodeLauncher
from .terminal import start_feature_in_terminal, detect_terminal
from .intelligence import IntelligenceEngine
from .prompt_builder import PromptBuilder
from .merge import MergeOrchestrator
from .init import EnhancedInitializer, ProjectContext
from .brainstorm import (
    BrainstormSession,
    parse_proposals,
    save_proposals,
    load_proposals,
    Proposal,
    ProposalStatus,
    check_shippable,
)
from .registry import MAX_PLANNED_FEATURES

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
    quick: bool = typer.Option(False, "--quick", "-q", help="Skip interactive questions"),
):
    """
    Initialize FlowForge in the current directory.

    Runs an enhanced initialization that:
    - Scans existing docs (README, CLAUDE.md, etc.)
    - Asks about your project vision and philosophy
    - Generates project-context.md for richer prompts

    Use --quick to skip interactive questions.
    """
    project_root = Path.cwd()

    if (project_root / ".flowforge").exists():
        if not Confirm.ask("FlowForge already initialized. Reinitialize?"):
            raise typer.Exit(0)

    console.print(f"\n🔨 Initializing FlowForge in [cyan]{project_root}[/cyan]\n")

    # Run enhanced initialization
    initializer = EnhancedInitializer(project_root)
    context = initializer.run(interactive=not quick)

    if context is None:
        raise typer.Exit(0)

    # Detect project settings
    detected = detect_project_settings(project_root)
    if name:
        detected.name = name
    else:
        detected.name = context.name

    # Create config
    config = FlowForgeConfig(project=detected)
    config.save(project_root)

    # Create registry
    registry = FeatureRegistry.create_new(project_root)

    # Create directory structure
    (project_root / ".flowforge" / "prompts").mkdir(parents=True, exist_ok=True)
    (project_root / ".flowforge" / "research").mkdir(parents=True, exist_ok=True)

    # Save project context
    context_path = context.save(project_root)

    console.print(f"\n✅ Project: [green]{detected.name}[/green]")
    console.print(f"✅ Main branch: [green]{detected.main_branch}[/green]")
    console.print(f"✅ CLAUDE.md: [green]{detected.claude_md_path}[/green]")
    console.print(f"✅ Project context: [green]{context_path}[/green]")
    if detected.build_command:
        console.print(f"✅ Build command: [green]{detected.build_command}[/green]")

    # Run GitHub health check
    _run_github_health_check(project_root, detected.name, auto_fix=not quick)

    # Import from roadmap if specified
    if from_roadmap:
        console.print(f"\n📥 Importing features from [cyan]{from_roadmap}[/cyan]...")
        count = import_features_from_roadmap(project_root, from_roadmap, registry)
        console.print(f"✅ Imported [green]{count}[/green] features")

    console.print("\n🎉 FlowForge initialized! Run [cyan]forge add[/cyan] to add features.")


@app.command()
def brainstorm(
    project: Optional[str] = typer.Option(None, "--project", "-p", help="Project name (for multi-project)"),
    paste: bool = typer.Option(False, "--paste", help="Paste Claude output to parse proposals"),
    review: Optional[str] = typer.Option(None, "--review", "-r", help="Review saved brainstorm session"),
):
    """
    Start a brainstorming session with Claude.

    Launches an interactive Claude session with a product strategist system prompt.
    When satisfied with ideas, say "that looks good" and Claude will output
    structured proposals in READY_FOR_APPROVAL format.

    Use --paste to parse Claude output you've copied.
    Use --review to review proposals from a saved session.
    """
    project_root, config, registry = get_context()

    # Read project context
    project_context = None
    context_path = project_root / ".flowforge" / "project-context.md"
    if context_path.exists():
        project_context = context_path.read_text()

    # Get existing features for context
    existing_features = [f.title for f in registry.list_features()]

    if review:
        # Review saved session
        proposals = load_proposals(project_root, review)
        if not proposals:
            console.print(f"[red]No proposals found for session: {review}[/red]")
            raise typer.Exit(1)
        _review_proposals(proposals, registry, project_root)
        return

    if paste:
        # Parse pasted output
        console.print("Paste the Claude output with READY_FOR_APPROVAL marker (Ctrl+D when done):\n")
        import sys
        pasted_text = sys.stdin.read()

        proposals = parse_proposals(pasted_text)
        if not proposals:
            console.print("[yellow]No proposals found in output.[/yellow]")
            console.print("[dim]Make sure Claude included the READY_FOR_APPROVAL marker.[/dim]")
            raise typer.Exit(1)

        console.print(f"\n[green]Found {len(proposals)} proposal(s)![/green]\n")
        _review_proposals(proposals, registry, project_root)
        return

    # Interactive brainstorm session
    session = BrainstormSession(
        project_root=project_root,
        project_name=config.project.name,
        project_context=project_context,
        existing_features=existing_features,
    )

    console.print(Panel(
        "[bold]Brainstorming Session[/bold]\n\n"
        "Chat with Claude about feature ideas.\n"
        "When ready, say 'that looks good' or 'ready to add these'.\n"
        "Claude will output structured proposals.\n\n"
        "[dim]After the session, run:[/dim]\n"
        "[cyan]forge brainstorm --paste[/cyan] and paste the READY_FOR_APPROVAL output.",
        title=f"FlowForge: {config.project.name}",
    ))

    session.start_interactive()

    # After session, prompt to parse
    console.print("\n[yellow]Session ended.[/yellow]")
    console.print("\nIf Claude output proposals, run:")
    console.print("  [cyan]forge brainstorm --paste[/cyan]")
    console.print("Then paste the READY_FOR_APPROVAL output to review proposals.")


def _review_proposals(proposals: list[Proposal], registry: FeatureRegistry, project_root: Path):
    """Interactive review of proposals - approve, decline, or defer each one."""
    console.print(f"\n[bold]Review {len(proposals)} Proposal(s)[/bold]\n")

    approved = []
    declined = []
    deferred = []

    for i, proposal in enumerate(proposals, 1):
        priority_color = "red" if proposal.priority == 1 else "yellow" if proposal.priority <= 3 else "dim"

        console.print(Panel(
            f"[bold]{proposal.title}[/bold]\n\n"
            f"{proposal.description}\n\n"
            f"[dim]Priority:[/dim] [{priority_color}]P{proposal.priority}[/{priority_color}]\n"
            f"[dim]Complexity:[/dim] {proposal.complexity}\n"
            f"[dim]Tags:[/dim] {', '.join(proposal.tags) if proposal.tags else '(none)'}\n"
            f"[dim]Rationale:[/dim] {proposal.rationale or '(none)'}",
            title=f"Proposal {i}/{len(proposals)}",
        ))

        choice = Prompt.ask(
            "Action",
            choices=["a", "d", "s", "q"],
            default="a",
        )

        if choice == "a":
            proposal.status = ProposalStatus.APPROVED
            approved.append(proposal)
            console.print("[green]✓ Approved[/green]\n")
        elif choice == "d":
            proposal.status = ProposalStatus.DECLINED
            declined.append(proposal)
            console.print("[red]✗ Declined[/red]\n")
        elif choice == "s":
            proposal.status = ProposalStatus.DEFERRED
            deferred.append(proposal)
            console.print("[yellow]⏸ Deferred[/yellow]\n")
        elif choice == "q":
            console.print("[yellow]Review cancelled.[/yellow]")
            break

    # Summary
    console.print("\n" + "=" * 60)
    console.print(f"\n[bold]Review Summary[/bold]\n")
    console.print(f"  [green]Approved:[/green] {len(approved)}")
    console.print(f"  [red]Declined:[/red] {len(declined)}")
    console.print(f"  [yellow]Deferred:[/yellow] {len(deferred)}")

    if approved:
        if Confirm.ask(f"\nAdd {len(approved)} approved proposal(s) to registry?"):
            for proposal in approved:
                feature_id = FeatureRegistry.generate_id(proposal.title)

                # Skip if exists
                if registry.get_feature(feature_id):
                    console.print(f"[yellow]Skipping '{proposal.title}' - already exists[/yellow]")
                    continue

                feature = Feature(
                    id=feature_id,
                    title=proposal.title,
                    description=proposal.description,
                    priority=proposal.priority,
                    complexity=Complexity(proposal.complexity) if proposal.complexity in [c.value for c in Complexity] else Complexity.MEDIUM,
                    tags=proposal.tags,
                )
                registry.add_feature(feature)
                console.print(f"[green]✓ Added: {proposal.title}[/green]")

            console.print(f"\n[green]✅ Added {len(approved)} features to registry![/green]")

    # Save session if there are deferred proposals
    if deferred:
        session_path = save_proposals(project_root, proposals)
        console.print(f"\n[dim]Deferred proposals saved to: {session_path}[/dim]")
        console.print(f"[dim]Review later with: forge brainstorm --review {session_path.stem}[/dim]")


@app.command()
def add(
    title: str = typer.Argument(..., help="Feature title"),
    description: Optional[str] = typer.Option(None, "--desc", "-d", help="Description"),
    parent: Optional[str] = typer.Option(None, "--parent", "-p", help="Parent feature ID"),
    spec: Optional[Path] = typer.Option(None, "--spec", "-s", help="Spec file path"),
    tags: Optional[str] = typer.Option(None, "--tags", "-t", help="Comma-separated tags"),
    complexity: Optional[str] = typer.Option(None, "--complexity", "-c", help="small/medium/large/epic"),
    priority: Optional[int] = typer.Option(None, "--priority", help="Priority (1=highest)"),
    status: Optional[str] = typer.Option(None, "--status", help="Initial status (idea/planned)"),
    project_dir: Optional[Path] = typer.Option(None, "-C", "--project-dir", help="Run as if forge was started in this directory"),
):
    """Add a new feature to the registry."""
    # Support -C like git for remote execution
    if project_dir:
        import os
        os.chdir(project_dir)
    project_root, config, registry = get_context()

    # Generate ID from title
    feature_id = FeatureRegistry.generate_id(title)

    # Check for existing
    if registry.get_feature(feature_id):
        console.print(f"[red]Feature already exists: {feature_id}[/red]")
        raise typer.Exit(1)

    # Interactive prompts for missing info (skip if not a TTY)
    import sys
    if not description and sys.stdin.isatty():
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

    # Parse status
    status_enum = FeatureStatus.IDEA  # Default to idea for quick capture
    if status:
        try:
            status_enum = FeatureStatus(status.lower())
        except ValueError:
            console.print(f"[yellow]Invalid status '{status}', using 'idea'[/yellow]")

    # Create feature
    feature = Feature(
        id=feature_id,
        title=title,
        description=description,
        status=status_enum,
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


# ============================================================================
# Shipping Machine Commands (Wave 4)
# ============================================================================


@app.command()
def build(
    idea: str = typer.Argument(..., help="Natural language description of what to build"),
    today: bool = typer.Option(False, "--today", "-t", help="Lock focus: ship this or nothing"),
    force: bool = typer.Option(False, "--force", "-f", help="Skip scope creep check"),
    no_clipboard: bool = typer.Option(False, "--no-clipboard", help="Don't copy prompt to clipboard"),
):
    """
    🚀 BUILD: The shipping machine command.

    One command to go from idea → Claude Code working:
      forge build "Add dark mode toggle"

    This automatically:
    1. Creates a feature from your idea
    2. Checks for scope creep (too big? suggests split)
    3. Enforces max 3 planned features (stay focused!)
    4. Creates worktree for isolated work
    5. Generates actionable implementation prompt
    6. Copies prompt to clipboard
    7. Shows instructions to launch Claude Code

    Use --today to lock focus: this feature or nothing else until shipped.
    """
    project_root, config, registry = get_context()

    console.print(f"\n🚀 [bold]BUILD[/bold]: {idea}\n")

    # Step 1: Check max planned features constraint
    planned_count = len(registry.list_features(status=FeatureStatus.PLANNED))
    in_progress_count = len(registry.list_features(status=FeatureStatus.IN_PROGRESS))

    if planned_count >= MAX_PLANNED_FEATURES:
        console.print(f"[red]❌ You have {MAX_PLANNED_FEATURES} planned features.[/red]")
        console.print(f"\n[yellow]Finish or delete one first to stay focused![/yellow]\n")

        planned_features = registry.list_features(status=FeatureStatus.PLANNED)
        console.print("Currently planned:")
        for f in planned_features[:MAX_PLANNED_FEATURES]:
            console.print(f"  • {f.title}")

        console.print(f"\n[dim]Hint: Run 'forge delete <id>' or 'forge start <id>' to make room.[/dim]")
        raise typer.Exit(1)

    # Step 2: Check for scope creep
    if not force:
        result = check_shippable(idea)

        if not result["shippable"] and result["warnings"]:
            console.print("[yellow]⚠️  Scope creep detected![/yellow]\n")

            for w in result["warnings"]:
                console.print(f"   • {w['issue']}")
                console.print(f"     [dim]{w['suggestion']}[/dim]\n")

            if result["suggestions"]:
                console.print("[yellow]Consider splitting into:[/yellow]")
                for s in result["suggestions"]:
                    console.print(f"   • {s}")

            console.print("")
            if not Confirm.ask("Continue anyway?"):
                console.print("\n[dim]Break it down, then try again![/dim]")
                raise typer.Exit(0)

    # Step 3: Create the feature
    feature_id = FeatureRegistry.generate_id(idea)

    if registry.get_feature(feature_id):
        console.print(f"[yellow]Feature already exists: {feature_id}[/yellow]")
        feature = registry.get_feature(feature_id)
    else:
        feature = Feature(
            id=feature_id,
            title=idea,
            description="",
            tags=["shipping-machine"],
            complexity=Complexity.MEDIUM,
            priority=1,  # Building it now = high priority
        )
        registry.add_feature(feature)
        console.print(f"✅ Created feature: [green]{feature_id}[/green]")

    # Step 4: Create worktree
    worktree_mgr = WorktreeManager(project_root, config.project.worktree_base)

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

    # Step 5: Generate actionable prompt
    console.print("📝 Generating implementation prompt...")

    intelligence = IntelligenceEngine(project_root)
    prompt_builder = PromptBuilder(project_root, registry, intelligence)

    prompt = prompt_builder.build_for_feature(
        feature_id,
        config.project.claude_md_path,
        include_experts=True,
        include_research=False,  # Action, not research
    )

    # Save prompt
    prompt_path = prompt_builder.save_prompt(feature_id, prompt)
    console.print(f"   ✅ Saved: [green]{prompt_path}[/green]")

    # Step 6: Copy to clipboard
    if not no_clipboard:
        try:
            import pyperclip
            pyperclip.copy(prompt)
            console.print("   ✅ Copied to clipboard")
        except Exception:
            console.print("   [yellow]Could not copy to clipboard[/yellow]")

    # Step 7: Update registry
    registry.update_feature(
        feature_id,
        status=FeatureStatus.IN_PROGRESS,
        branch=f"feature/{feature_id}",
        worktree_path=str(worktree_path),
        prompt_path=str(prompt_path),
    )

    # Step 8: Show launch instructions
    remaining = MAX_PLANNED_FEATURES - (planned_count - 1)  # One less since we started it

    console.print("\n" + "=" * 60)
    console.print(f"\n[bold green]🚀 Ready to build![/bold green]")
    console.print(f"\n[dim]Slots remaining: {remaining}/{MAX_PLANNED_FEATURES}[/dim]\n")

    console.print("Launch Claude Code:\n")
    console.print(f"  [cyan]cd {worktree_path}[/cyan]")
    console.print(f"  [cyan]{config.project.claude_command} {' '.join(config.project.claude_flags)}[/cyan]")
    console.print("\nPaste the prompt and start building!\n")

    if today:
        console.print("[yellow]🎯 TODAY MODE: Ship this or nothing![/yellow]")
        console.print("[dim]Run 'forge ship' when done.[/dim]")

    console.print("=" * 60)


@app.command()
def ship(
    feature_id: Optional[str] = typer.Argument(None, help="Feature ID to ship (auto-detects if only one in-progress)"),
    skip_validation: bool = typer.Option(False, "--skip-validation", "-s", help="Skip build validation"),
    keep_worktree: bool = typer.Option(False, "--keep", "-k", help="Keep worktree after shipping"),
):
    """
    🚢 SHIP: One-click merge and celebrate.

    Completes the shipping machine workflow:
      forge ship

    This automatically:
    1. Finds your in-progress feature
    2. Marks it as review
    3. Checks for conflicts (resolves if possible)
    4. Merges into main
    5. Cleans up worktree
    6. Celebrates!

    If you have multiple features in-progress, specify the ID.
    """
    project_root, config, registry = get_context()

    # Find feature to ship
    if feature_id:
        feature = registry.get_feature(feature_id)
        if not feature:
            console.print(f"[red]Feature not found: {feature_id}[/red]")
            raise typer.Exit(1)
    else:
        # Auto-detect: find in-progress features
        in_progress = registry.list_features(status=FeatureStatus.IN_PROGRESS)
        review_features = registry.list_features(status=FeatureStatus.REVIEW)

        # Also consider review features as shippable
        shippable = in_progress + review_features

        if not shippable:
            console.print("[yellow]No features in progress or review to ship.[/yellow]")
            console.print("[dim]Run 'forge build \"your idea\"' to start one.[/dim]")
            raise typer.Exit(1)

        if len(shippable) == 1:
            feature = shippable[0]
            console.print(f"\n🚢 [bold]SHIP[/bold]: {feature.title}\n")
        else:
            console.print("[yellow]Multiple features in progress/review. Specify which to ship:[/yellow]\n")
            for f in shippable:
                console.print(f"  • [cyan]forge ship {f.id}[/cyan] - {f.title}")
            raise typer.Exit(1)

    # Ensure feature is shippable
    if feature.status not in [FeatureStatus.IN_PROGRESS, FeatureStatus.REVIEW]:
        console.print(f"[yellow]Feature is {feature.status.value}, not in-progress or review.[/yellow]")
        raise typer.Exit(1)

    # Step 1: Mark as review if in-progress
    if feature.status == FeatureStatus.IN_PROGRESS:
        registry.update_feature(feature.id, status=FeatureStatus.REVIEW)
        console.print("✅ Marked as ready for review")

    # Step 2: Check for conflicts
    console.print("🔍 Checking for conflicts...")

    orchestrator = MergeOrchestrator(
        project_root,
        registry,
        config.project.main_branch,
        config.project.build_command,
    )

    conflict_result = orchestrator.check_conflicts(feature.id)

    if not conflict_result.success:
        console.print(f"\n[yellow]⚠️  Conflicts detected in {len(conflict_result.conflict_files)} file(s).[/yellow]\n")

        for cf in conflict_result.conflict_files:
            console.print(f"   • {cf}")

        console.print("\n[dim]Attempting auto-resolution...[/dim]")

        # Try to sync (rebase onto main)
        success, message = orchestrator.sync_feature(feature.id)

        if not success:
            console.print(f"\n[red]❌ Could not auto-resolve conflicts.[/red]")
            console.print(f"[dim]{message}[/dim]")
            console.print("\n[yellow]Manual resolution needed:[/yellow]")
            console.print(f"  1. cd {feature.worktree_path}")
            console.print(f"  2. Resolve conflicts in the files above")
            console.print(f"  3. git add . && git rebase --continue")
            console.print(f"  4. forge ship {feature.id}")
            raise typer.Exit(1)

        console.print("   ✅ Conflicts resolved!")

    # Step 3: Merge
    console.print(f"🔀 Merging into {config.project.main_branch}...")

    merge_result = orchestrator.merge_feature(
        feature.id,
        validate=not skip_validation,
        auto_cleanup=not keep_worktree,
    )

    if not merge_result.success:
        console.print(f"\n[red]❌ Merge failed: {merge_result.message}[/red]")

        if merge_result.validation_output:
            console.print("\n[yellow]Build validation output:[/yellow]")
            console.print(merge_result.validation_output[:500])

        console.print("\n[dim]Fix the issue and try again with 'forge ship'[/dim]")
        raise typer.Exit(1)

    # Step 4: Record the ship and update streak!
    stats = registry.record_ship()

    # Step 5: Celebrate!
    console.print("\n" + "=" * 60)
    console.print("\n[bold green]🎉 SHIPPED![/bold green]\n")
    console.print(f"   Feature: [cyan]{feature.title}[/cyan]")
    console.print(f"   Branch:  merged into {config.project.main_branch}")

    if not keep_worktree:
        console.print("   Cleanup: worktree removed")

    # Show streak (the dopamine hit!)
    console.print(f"\n   {registry.get_streak_display()} (Best: {stats.longest_streak})")
    console.print(f"   [dim]Total shipped: {stats.total_shipped}[/dim]")

    # Show remaining planned
    planned = registry.list_features(status=FeatureStatus.PLANNED)
    completed = registry.list_features(status=FeatureStatus.COMPLETED)

    console.print(f"\n   [dim]Completed: {len(completed)} | Planned: {len(planned)}[/dim]")

    if planned:
        console.print("\n[yellow]What's next?[/yellow]")
        for p in planned[:3]:
            console.print(f"   • forge build \"{p.title}\"")
    else:
        console.print("\n[green]🎊 Backlog clear! Time to brainstorm.[/green]")
        console.print("   forge brainstorm")

    console.print("\n" + "=" * 60)


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
def edit(
    feature_id: str = typer.Argument(..., help="Feature ID to edit"),
    title: Optional[str] = typer.Option(None, "--title", "-t", help="New title"),
    description: Optional[str] = typer.Option(None, "--desc", "-d", help="New description"),
    status: Optional[str] = typer.Option(None, "--status", "-s", help="New status"),
    priority: Optional[int] = typer.Option(None, "--priority", "-p", help="New priority"),
    complexity: Optional[str] = typer.Option(None, "--complexity", "-c", help="New complexity"),
    tags: Optional[str] = typer.Option(None, "--tags", help="Comma-separated tags (replaces existing)"),
):
    """Edit a feature's attributes."""
    project_root, config, registry = get_context()

    feature = registry.get_feature(feature_id)
    if not feature:
        console.print(f"[red]Feature not found: {feature_id}[/red]")
        raise typer.Exit(1)

    # Build updates from provided options
    updates = {}
    if title is not None:
        updates["title"] = title
    if description is not None:
        updates["description"] = description
    if status is not None:
        updates["status"] = status
    if priority is not None:
        updates["priority"] = priority
    if complexity is not None:
        updates["complexity"] = complexity
    if tags is not None:
        updates["tags"] = [t.strip() for t in tags.split(",")]

    if not updates:
        console.print("[yellow]No updates provided. Use --help to see available options.[/yellow]")
        raise typer.Exit(1)

    try:
        updated = registry.update_feature(feature_id, **updates)
        console.print(f"\n✅ Updated feature: [green]{updated.title}[/green]")
        console.print(f"   Status: {updated.status.value}")
        console.print(f"   Priority: {updated.priority}")
        if updated.tags:
            console.print(f"   Tags: {', '.join(updated.tags)}")
    except ValueError as e:
        console.print(f"[red]Error: {e}[/red]")
        raise typer.Exit(1)


@app.command()
def delete(
    feature_id: str = typer.Argument(..., help="Feature ID to delete"),
    force: bool = typer.Option(False, "--force", "-f", help="Force delete (even if in-progress or has children)"),
):
    """Delete a feature from the registry."""
    project_root, config, registry = get_context()

    feature = registry.get_feature(feature_id)
    if not feature:
        console.print(f"[red]Feature not found: {feature_id}[/red]")
        raise typer.Exit(1)

    # Confirm deletion
    if not force:
        if not Confirm.ask(f"Delete feature '{feature.title}'?"):
            console.print("[yellow]Deletion cancelled.[/yellow]")
            raise typer.Exit(0)

    try:
        registry.remove_feature(feature_id, force=force)
        console.print(f"\n✅ Deleted feature: [green]{feature.title}[/green]")
    except ValueError as e:
        console.print(f"[red]Error: {e}[/red]")
        console.print("[dim]Use --force to override safety checks.[/dim]")
        raise typer.Exit(1)


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
    open_terminal: bool = typer.Option(True, "--open/--no-open", help="Auto-open terminal with Claude Code"),
    terminal: str = typer.Option("auto", "--terminal", "-t", help="Terminal to use: warp, iterm, terminal, auto"),
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

    # Step 5: Launch terminal or show instructions
    console.print("\n" + "=" * 60)
    console.print("\n[bold green]Ready to implement![/bold green]\n")

    if open_terminal:
        console.print("🖥️  Opening terminal with Claude Code...")
        success, message = start_feature_in_terminal(
            worktree_path=worktree_path,
            feature_title=feature.title,
            claude_command=config.project.claude_command,
            claude_flags=config.project.claude_flags,
            terminal=terminal,
        )
        if success:
            console.print(f"   ✅ {message}")
            console.print("\n[bold]Just paste the prompt from your clipboard to begin![/bold]")
        else:
            console.print(f"   [yellow]{message}[/yellow]")
    else:
        console.print("Launch Claude Code with:\n")
        console.print(f"  [cyan]cd {worktree_path}[/cyan]")
        console.print(f"  [cyan]{config.project.claude_command} {' '.join(config.project.claude_flags)}[/cyan]")
        console.print("\nThen paste the prompt from your clipboard.")

    console.print("\n" + "=" * 60)


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


def _run_github_health_check(project_root: Path, project_name: str, auto_fix: bool = True) -> None:
    """
    Run GitHub health check and optionally auto-fix issues.

    Integrated into forge init to catch git/GitHub issues early.
    """
    console.print("\n🔍 [bold]Checking GitHub health...[/bold]")

    checker = GitHubHealthChecker(project_root)
    report = checker.run_all_checks()

    # Display check results
    for check in report.checks:
        if check.status == HealthStatus.OK:
            console.print(f"  ✅ {check.name}: {check.message}")
        elif check.status == HealthStatus.WARNING:
            console.print(f"  ⚠️  [yellow]{check.name}[/yellow]: {check.message}")
        else:
            console.print(f"  ❌ [red]{check.name}[/red]: {check.message}")

    # Auto-fix if requested
    if auto_fix and report.auto_fix_available:
        console.print(f"\n🔧 Auto-fixing: {', '.join(report.auto_fix_available)}")
        results = checker.auto_fix(report.auto_fix_available)
        for issue, success in results.items():
            if success:
                console.print(f"  ✅ Fixed: {issue}")
            else:
                console.print(f"  ❌ Could not fix: {issue}")

    # Check for similar repos
    similar = checker.find_similar_repos()
    if similar:
        console.print(f"\n📋 [yellow]Found {len(similar)} similar repos on GitHub:[/yellow]")
        for repo in similar[:5]:  # Show top 5
            console.print(f"  • [cyan]{repo.full_name}[/cyan] - {repo.similarity_reason}")
            if repo.description:
                console.print(f"    {repo.description[:60]}...")
        console.print("  [dim]Consider archiving old/duplicate repos.[/dim]")

    # Final status
    if report.overall_status == HealthStatus.OK:
        console.print("\n✅ GitHub health: [green]Good[/green]")
    elif report.overall_status == HealthStatus.WARNING:
        console.print("\n⚠️  GitHub health: [yellow]Needs attention[/yellow]")
        console.print("  [dim]Worktrees may not work correctly. Fix issues above.[/dim]")
    else:
        console.print("\n❌ GitHub health: [red]Issues detected[/red]")
        console.print("  [dim]Fix issues above before using forge start.[/dim]")


if __name__ == "__main__":
    app()
