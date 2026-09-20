// Workspace sidebar that shows the working directory's last path segment
// (e.g. "dotfiles") above the git branch, instead of cmux's default full
// path (e.g. "code/github.com/0x63616c/dotfiles" below "main"). The name's
// text color is a stable hash of the directory basename, so each repo gets
// a consistent, distinguishable color across sessions.
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(basename(w.directory))
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(colorForName(basename(w.directory)))
                if let b = w.branch {
                    HStack(spacing: 4) {
                        Text(b).font(.caption).foregroundColor(.secondary)
                        if w.dirty {
                            Text("*").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(w.selected ? Color("#7f7f7f3d") : Color.clear)
        .cornerRadius(8)
        .onTapGesture { cmux("workspace.select", workspace_id: w.id) }
    }
}
