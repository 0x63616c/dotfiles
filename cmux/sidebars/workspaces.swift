// Workspace sidebar: a cleaner take on cmux's native row.
//
//   ┃ Title                  ● Running   <- title; Running while Claude spins
//   ┃ dotfiles                    main*   <- repo basename (hash-tinted) · branch
//
// The left accent bar and the repo name share a colour that is a stable hash
// of the directory basename, so each repo stays recognisable across sessions.
// The bar is bright on the selected row and dim otherwise; the selected row
// also gets a soft rounded wash behind it, and a row with unread notifications
// gets that wash in its repo colour.
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

// This cmux build (0.64.22) gives the sidebar no agent status, so it is read
// off two things it does give us. Claude Code spins ◐◓◑◒ at the front of the
// terminal title while it works and rests on ✳ when idle, so a spinner glyph
// in the title means "running". And cmux counts a notification as unread on
// any workspace you are not looking at, and Claude fires one when it finishes
// or stops for input, so unread > 0 means "waiting on you".
func isWorking(_ title: String) -> Bool {
    return title.contains("◐") || title.contains("◓") || title.contains("◑") || title.contains("◒")
}

func row(_ w) -> some View {
    let repo = basename(w.directory)
    let tint = colorForName(repo)
    let working = isWorking(w.title)
    let waiting = w.unread > 0

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
    // Wash: neutral on the selected row; the repo tint on any row with unread
    // notifications, i.e. an agent finished or stopped while you were elsewhere.
    .background {
        RoundedRectangle(cornerRadius: 8)
            .fill(waiting ? tint : "#FFFFFF")
            .opacity(waiting ? (w.selected ? 0.22 : 0.14) : (w.selected ? 0.09 : 0.0))
    }
    .contentShape(Rectangle())
    .onTapGesture { cmux("workspace.select", workspace_id: w.id) }
}

VStack(alignment: .leading, spacing: 4) {
    // Breathing room under the traffic lights; .padding(n) can't do top-only.
    Rectangle().fill("#00000000").frame(height: 10)
    ForEach(workspaces) { w in
        row(w)
    }
}
.padding(2)
