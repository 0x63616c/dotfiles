// Workspace sidebar: a cleaner take on cmux's native row.
//
//   ┃ Title                  ● Running   <- title; Running/Needs you from cmux
//   ┃ dotfiles                    main*   <- repo basename (hash-tinted) · branch
//
// The left accent bar and the repo name share a colour that is a stable hash
// of the directory basename, so each repo stays recognisable across sessions.
// The bar is bright on the selected row and dim otherwise; the selected row
// also gets a soft rounded wash behind it, and a row whose agent is waiting on
// you gets that wash in its repo colour.
//
// Rows use `.onTapGesture` rather than `Button` so the whole row is a hit
// target (the interpreter's `Button` only hit-tests non-transparent content).
// Interpreter gotchas that wreck the layout:
//   - `.fixedSize(horizontal:vertical:)` is read as a bare `.fixedSize()`,
//     which collapses every Spacer and shrink-wraps the row.
//   - `.padding(.horizontal, n)` / `.padding(.vertical, n)` are read as
//     `.padding(n)` on every edge, so they stack. Only use `.padding(n)`.
//
// Select it: right-click the sidebar toggle button -> "workspaces"
// Preview as a pane without switching the left sidebar: `cmux sidebar open workspaces`

func basename(_ path: String) -> String {
    let parts = path.split(separator: "/")
    if parts.count > 0 {
        return String(parts[parts.count - 1])
    }
    return path
}

func colorForName(_ name: String) -> String {
    let letters = [
        "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    ]
    let lower = name.lowercased()
    var hash = name.count
    for i in letters.indices {
        let letter = letters[i]
        if lower.contains(letter) {
            hash = hash + (i + 1) * (i + 3)
        }
    }
    // Muted, dark-terminal-friendly palette (Tokyo Night-ish).
    let palette = [
        "#F7768E", "#FF9E64", "#E0AF68", "#9ECE6A", "#73DACA",
        "#7DCFFF", "#7AA2F7", "#BB9AF7", "#FF7AB2", "#C0A36E",
    ]
    let index = hash % palette.count
    return palette[index]
}

// Agent status comes straight from cmux: `w.agents` (0.64.23+) is the list of
// coding-agent sessions the workspace hosts, each with a real
// idle|working|needs_input|ended status. needs_input wins over working, so a
// workspace where one agent is asking and another is grinding reads as the one
// that wants you.
//
// Note the interpreter quirk: `w.agents != nil` is FALSE even when the field is
// there. Optional fields must be unwrapped with `if let`, never compared to nil.
func agentState(_ w) -> String {
    var any = false
    var working = false
    var needs = false
    if let ags = w.agents {
        for a in ags {
            any = true
            if a.status == "working" { working = true }
            if a.status == "needs_input" { needs = true }
        }
    }
    if needs { return "needs_input" }
    if working { return "working" }
    if any { return "idle" }
    return "none"
}

// Fallback for a workspace cmux registers no agent session for: Claude Code
// spins ◐◓◑◒ at the front of the terminal title while it works.
func isWorking(_ title: String) -> Bool {
    return title.contains("◐") || title.contains("◓") || title.contains("◑") || title.contains("◒")
}

func row(_ w) -> some View {
    let repo = basename(w.directory)
    let tint = colorForName(repo)
    let state = agentState(w)
    let working = state == "working" || (state == "none" && isWorking(w.title))
    // "Waiting on you" is an agent that stopped for input; with no agent
    // session to ask, fall back to cmux's unread count.
    let waiting = state == "needs_input" || (state == "none" && w.unread > 0)

    HStack(alignment: .top, spacing: 10) {
        // Accent bar: repo colour, bright when selected.
        RoundedRectangle(cornerRadius: 1.5)
            .fill(tint)
            .frame(width: 3, height: 45)
            .opacity(w.selected ? 1.0 : 0.35)

        VStack(alignment: .leading, spacing: 7) {
            // Line 1: title + trailing counters.
            HStack(spacing: 6) {
                Text(w.title)
                    .font(.system(size: 16))
                    .fontWeight(w.selected ? .semibold : .medium)
                    .foregroundColor(w.selected ? .primary : "#D0D0D0")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if waiting {
                    HStack(spacing: 4) {
                        Circle().fill("#E0AF68").frame(width: 7, height: 7)
                        Text("Needs you").font(.system(size: 13)).foregroundColor("#E0AF68")
                    }
                }
                if working {
                    // Blinks: the sidebar re-renders about once a second, so
                    // the dot dims on odd seconds and comes back on even ones.
                    HStack(spacing: 4) {
                        Circle().fill("#7AA2F7").frame(width: 7, height: 7)
                            .opacity(clock.second % 2 == 0 ? 1.0 : 0.25)
                        Text("Running").font(.system(size: 13)).foregroundColor("#7AA2F7")
                    }
                }
                if w.tabCount > 1 {
                    Text("\(w.tabCount)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.tertiary)
                }
            }

            // Line 2: repo on the left, branch (with dirty marker) on the right.
            HStack(spacing: 5) {
                Text(repo)
                    .font(.system(size: 16))
                    .fontWeight(.medium)
                    .foregroundColor(tint)
                    .lineLimit(1)
                Spacer()
                if let b = w.branch {
                    Text(b)
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if w.dirty {
                        Circle()
                            .fill("#E0AF68")
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
    }
    .padding(9)
    .frame(maxWidth: .infinity, alignment: .leading)
    // Wash: neutral on the selected row; the repo tint on any row whose agent
    // stopped for input, so "it wants you" reads from across the screen.
    .background {
        RoundedRectangle(cornerRadius: 8)
            .fill(waiting ? tint : "#FFFFFF")
            .opacity(waiting ? (w.selected ? 0.22 : 0.14) : (w.selected ? 0.09 : 0.0))
    }
    .contentShape(Rectangle())
    .onTapGesture { cmux("workspace.select", workspace_id: w.id) }
    // A custom sidebar replaces the built-in row wholesale, including its
    // right-click menu, so the verbs have to be re-declared here.
    .contextMenu {
        Button(w.pinned ? "Unpin" : "Pin") {
            cmux("workspace.action", action: w.pinned ? "unpin" : "pin", workspace_id: w.id)
        }
        Button(w.unread > 0 ? "Mark as Read" : "Mark as Unread") {
            cmux("workspace.action", action: w.unread > 0 ? "mark_read" : "mark_unread", workspace_id: w.id)
        }
        Divider()
        Menu("Move") {
            Button("Move Up") { cmux("workspace.action", action: "move_up", workspace_id: w.id) }
            Button("Move Down") { cmux("workspace.action", action: "move_down", workspace_id: w.id) }
            Button("Move to Top") { cmux("workspace.action", action: "move_top", workspace_id: w.id) }
        }
        Divider()
        Button("Close Others") { cmux("workspace.action", action: "close_others", workspace_id: w.id) }
        Button("Close") { cmux("workspace.close", workspace_id: w.id) }
    }
}

VStack(alignment: .leading, spacing: 4) {
    // Breathing room under the traffic lights; .padding(n) can't do top-only.
    Rectangle().fill("#00000000").frame(height: 10)
    // Reorderable, not ForEach: rows become draggable and a drop runs
    // `workspace.reorder`, which both moves the row and persists the order
    // (cmux remembers it). Do not reach for List/.onMove/.draggable.
    Reorderable(workspaces, move: "workspace.reorder") { w in
        row(w)
    }
}
.padding(2)
