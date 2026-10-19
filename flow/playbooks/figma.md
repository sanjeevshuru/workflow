# Playbook: Figma designs (multi-node flows)

One feature usually spans several Figma nodes: a list screen, a detail screen, an edit modal, a confirm dialog, and empty, loading and error states. Those nodes can come as several links, sometimes across several files, or as one Section or page link that contains them all. Always treat the design as a **flow of nodes**, never a single link.

## Figma link anatomy
`https://www.figma.com/design/<fileKey>/<file-name>?node-id=<a>-<b>`

- `fileKey` is the path segment after `/design/` (or `/file/`). For branch links (`/design/<fileKey>/branch/<branchKey>/…`), use the `branchKey`.
- `node-id` in the URL uses a dash (`12-345`). The MCP tools take a colon (`12:345`).
- A link without `node-id` points at the whole file. In that case, ask the user for frame links ("right-click the frame → Copy link to selection"). You can also call `get_metadata` on the page to list frames, then confirm with the user.

## Part 1: Collect and manifest (step 01, orchestrator)
**Precondition:** `status.md` → Scope `type` is `frontend` or `fullstack`, confirmed by the user in triage. For `backend` tickets, don't run this part and don't call the Figma MCP, even when the ticket has Figma links. Those links are reference only.

1. **Collect** every Figma link from:
   - the ticket's Jira **Figma** and **Design** fields, plus any other field whose value has a figma.com URL (`ticket.md` → Figma links found; see `config/jira.md`)
   - the ticket description and comments
   - the parent epic and linked issues, including their Figma fields
   - the source doc sections the analyst cites
   - the links in `status.md` → Inputs

   Record where each link came from.
2. **Dedupe** by `fileKey + nodeId`.
3. **Expand** containers. For each link, call the Figma MCP `get_metadata` once. If the node is a SECTION, CANVAS (page), or a frame whose direct children are themselves top-level screen frames, list those child frames as separate rows. `get_metadata` returns structure only and is the cheap call.
4. **Classify** each row's kind from its name, size and structure: `screen`, `modal`, `drawer`, `state` (empty/loading/error/success), `component`, or `annotation`. Mark the kind `?` if unsure, and add a question.
5. **Order**. Propose the flow order and transitions from the frame names, their positions on the canvas, and any arrows or annotations. Prototype links are not reliably exposed, so the order is a **proposal to confirm**, never a fact.
6. **Map AC**. Link each row to the ACs it serves.
7. Write `runs/<KEY>/figma-flow.md` from `flow/templates/figma-flow.md`, including the call budget estimate.
8. Add these questions to the open questions:
   - "Is this the complete set of screens and states for <KEY>?"
   - "Is this order and these transitions correct?" (shown as `F1 → F2 on <action>`)
   - Any AC with no node: "No design for AC<n>. Is there one, or should we follow existing UI patterns?"
   - Any node with no AC: "F<n> '<name>' is not covered by any AC. Is it in scope?"
   - Variants or duplicates (`v1`, `v2`, `old`, `final`): "Which is current?"
   - A missing empty, loading or error state when the screen loads data: "Is there a design for these states?"

## Part 2: Fetch per node (step 02, frontend-planner)
Only for rows the user confirmed as in scope.

1. **Budget check.** The team's seat type is **unknown** (`setup/mcp.md` → Seat limits), so don't block on it. Keep calls minimal instead: one `get_variable_defs` per file, then `get_screenshot` + `get_design_context` only for in-scope nodes, and never refetch a node already `fetched`. If a call fails with a rate-limit or quota error, stop. Mark the remaining rows `pending`, record it in `status.md` → Notes, and ask the user whether to wait, continue with screenshots only, or use exported images.
2. Call `get_variable_defs` **once per file** for the design tokens (colors, spacing, typography).
3. For each node:
   1. Call `get_screenshot`, the visual reference.
   2. Call `get_design_context` for layout, components and styles. If the response is flagged as sparse, request its visible child nodes instead of guessing.
   3. Write `runs/<KEY>/figma/<nodeId with : replaced by ->.md` with these sections:
      - layout structure
      - components used (with the Figma component name, and any Code Connect mapping if returned)
      - **Design-system mapping**: Map Figma components directly against existing `closio-web-v2` shared components (`src/components/` like `BaseDataTable`, `MonthYearPicker`, `MessageCard`) and module components (`src/views/<module>/components/`). Note required props, slots, Pinia state actions, and validation rules.
      - tokens
      - every visible text string (verbatim, for i18n)
      - interactive elements and what they appear to do
      - states shown
      - anything unclear
   4. Update the row's `Fetch status` in `figma-flow.md` to `fetched`.
   5. Run calls in parallel when the host allows it, otherwise one at a time. Because progress is kept in files, a sequential run can resume mid-list.
4. **Shared components.** When a component appears in several nodes, describe it fully in the first node's notes. The other nodes reference it (`see F2 notes → Components → FilterBar`).
5. Never design from imagination. If a node cannot be fetched, mark it `failed` and ask the user for a working link or an exported image.

## When the Figma MCP is unavailable
Say so. Ask the user to either fix the connection (`setup/mcp.md`) or provide PNG exports and a written flow. Record this in `status.md` → Notes. Plans built from exports must say so in their header.
