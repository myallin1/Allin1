# Allin1 Super App - Trae AI Developer Guidelines

## 1. Project Context & Brand Identity

- **Business:** NJ Tech (Mobile, Laptops & Electronic Gadgets Service Center), located in Erode, Tamil Nadu.
- **App Name:** Allin1 Super App.
- **Core Theme:** Premium Pink & White signature theme. Always utilize existing color variables (e.g., `kPink`, `kBg`, `kSurface`, `kText`).

## 2. UI/UX Design Standards

- **Inspiration:** Follow PhonePe, Spotify, and Zaaroz app design standards for premium feel.
- **Components:** \* Use rounded corners heavily (`BorderRadius.circular(16)` to `24`).
  - Keep layouts clean, breathable, and avoid cluttered elements.
  - Use optimistic UI updates for Wallets and Rewards.
- **Banners & Ads:** Implement auto-scrolling features (PageViews with Timers) for promotional banners at the top or bottom of tabs.

## 3. Coding & Execution Rules

- **Surgical Strikes Only:** NEVER rewrite or delete entire files unless explicitly instructed. Apply exact, localized patches to specific widgets or methods.
- **Zero Breakage:** Ensure new UI features (like buttons or carousels) integrate seamlessly without breaking existing layouts, `SingleChildScrollView` structures, or Stack positions.
- **No Hallucinations:** Do not invent non-existent third-party packages or dummy assets. Stick strictly to the provided codebase architecture and imports.

***

## 4. graphify Rules (Knowledge Graph Navigation)

This project has a graphify knowledge graph at `graphify-out/`.

Rules:

- Before answering architecture or codebase questions, read `graphify-out/GRAPH_REPORT.md` for god nodes and community structure.
- If `graphify-out/wiki/index.md` exists, navigate it instead of reading raw files.
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files.
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost).

## 5. Repository Knowledge & Durable Memory (DOCS-INDEX)

- **Agent Neutrality:** Agents must prioritize durable repository contracts (`AGENTS.md`, maps) over conversational memory. Do not rely on chat history for architectural rules.
- **Read Before Editing:** Agents MUST read this root `AGENTS.md` and any relevant child `AGENTS.md` before making changes.
- **Update After Editing:** If a meaningful change affects architecture, permissions, routing, or workflows, the agent MUST update this `AGENTS.md` (or the child doc) before concluding the task.

## 6. GitHub, PR, & Versioning Workflow

Treat feature requests and bug reports as issue work.

- **Branch Naming:** Use `agent/issue-<number>-<slug>` for existing issues, or `agent/<type>-<slug>` for issue-less work.
- **Versioning:** Use semantic versioning (vX.Y.Z).
- **Changelog:** Record user-facing, product, architecture, and workflow changes in `CHANGELOG.md` before a merge or release.

## 7. Hierarchical Documentation & Design Contracts

- **Child Docs:** When a folder becomes a durable boundary with its own specific rules, create a nested child `AGENTS.md` inside that folder. Child docs control local work details but cannot weaken root DOCS-INDEX rules.
- **Design Contracts:** Any major visual/UI project should route layout and brand work to a `Design.md` file before scaffolding the actual code.

## 8. Closeout & Verification Protocol

1. Run `flutter analyze` and ensure ZERO errors.
2. Run `graphify update .` to keep the AST graph current (as per Section 4).
3. Remove stale or contradictory text from documentation.
4. Ensure branch naming, versioning, and CHANGELOG updates are complete if applicable.

