// Workspace sidebar: a cleaner take on cmux's native row.
//
//   ┃ Title                          2   <- title, tab count / unread badge
//   ┃ dotfiles  main*                    <- repo basename (hash-tinted) · branch
//   ┃ ● Running                          <- agent status, only when an agent is live
//
// The left accent bar and the repo name share a colour that is a stable hash
// of the directory basename, so each repo stays recognisable across sessions.
// The bar is bright on the selected row and dim otherwise; the selected row
// also gets a soft rounded wash behind it.
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

func agentStatus(_ w) -> String {
    if w.agents != nil && w.agents.count > 0 {
        return w.agents[0].status
    }
    return ""
}

func row(_ w) -> some View {
    let repo = basename(w.directory)
    let tint = colorForName(repo)
    let status = agentStatus(w)

    HStack(alignment: .top, spacing: 10) {
        // Accent bar: repo colour, bright when selected.
        RoundedRectangle(cornerRadius: 1.5)
            .fill(tint)
            .frame(width: 3, height: 38)
            .opacity(w.selected ? 1.0 : 0.35)

        VStack(alignment: .leading, spacing: 4) {
            // Line 1: title + trailing counters.
            HStack(spacing: 6) {
                Text(w.title)
                    .font(.system(size: 16))
                    .fontWeight(w.selected ? .semibold : .medium)
                    .foregroundColor(w.selected ? .primary : "#D0D0D0")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if w.unread > 0 {
                    // Spaces, not .padding(.horizontal): the interpreter reads
                    // that as padding on every edge (see the header).
                    Text(" \(w.unread) ")
                        .font(.system(size: 13, design: .monospaced))
                        .bold()
                        .foregroundColor("#1A1A22")
                        .padding(4)
                        .background { Capsule().fill("#E0AF68") }
                } else if w.tabCount > 1 {
                    Text("\(w.tabCount)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.tertiary)
                }
            }

            // Line 2: repo · branch (dirty marker), agent status pill.
            HStack(spacing: 5) {
                Text(repo)
                    .font(.system(size: 16))
                    .fontWeight(.medium)
                    .foregroundColor(tint)
                    .lineLimit(1)
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
                Spacer()
                if status == "working" {
                    HStack(spacing: 4) {
                        Circle().fill("#7AA2F7").frame(width: 7, height: 7)
                        Text("Running").font(.system(size: 13)).foregroundColor("#7AA2F7")
                    }
                } else if status == "needs_input" {
                    HStack(spacing: 4) {
                        Circle().fill("#FF9E64").frame(width: 7, height: 7)
                        Text("Needs input").font(.system(size: 13)).fontWeight(.semibold).foregroundColor("#FF9E64")
                    }
                }
            }
        }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
        RoundedRectangle(cornerRadius: 8)
            .fill(w.selected ? "#FFFFFF" : "#00000000")
            .opacity(w.selected ? 0.09 : 0.0)
    }
    .contentShape(Rectangle())
    .onTapGesture { cmux("workspace.select", workspace_id: w.id) }
}

VStack(alignment: .leading, spacing: 4) {
    ForEach(workspaces) { w in
        row(w)
    }
}
.padding(6)
