// Workspace sidebar matching cmux's native row layout (title, status message,
// agent status, branch · directory) but with the bottom line's directory
// shortened to its last path segment (e.g. "dotfiles") instead of the full
// path (e.g. "~/code/github.com/0x63616c/dotfiles"). The title's text color
// is a stable hash of the directory basename, so each repo stays visually
// distinguishable across sessions.
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
    let palette = [
        "red", "orange", "yellow", "green", "teal",
        "blue", "indigo", "purple", "pink", "brown",
    ]
    let index = hash % palette.count
    return palette[index]
}

VStack(alignment: .leading, spacing: 2) {
    ForEach(workspaces) { w in
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if w.unread > 0 {
                    ZStack {
                        Circle().fill("orange").frame(width: 16, height: 16)
                        Text("\(w.unread)").font(.caption2).bold().foregroundColor(.white)
                    }
                }
                Text(w.title)
                    .font(.system(size: 13))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .foregroundColor(colorForName(basename(w.directory)))
            }
            if let msg = w.latestMessage {
                Text(msg).font(.caption).lineLimit(1).foregroundColor(.secondary)
            }
            if let agents = w.agents {
                if agents.count > 0 {
                    let status = agents[0].status
                    if status == "working" {
                        Text("Running").font(.caption2).foregroundColor(.blue)
                    } else if status == "needs_input" {
                        Text("Needs input").font(.caption2).foregroundColor(.orange)
                    }
                }
            }
            if let b = w.branch {
                Text("\(b)\(w.dirty ? "*" : "") · \(basename(w.directory))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text(basename(w.directory)).font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(w.selected ? Color("#7f7f7f3d") : Color.clear)
        .cornerRadius(8)
        .onTapGesture { cmux("workspace.select", workspace_id: w.id) }
    }
}
