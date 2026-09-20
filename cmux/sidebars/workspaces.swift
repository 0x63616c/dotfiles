// Workspace sidebar that shows the working directory's last path segment
// (e.g. "dotfiles") above the git branch, instead of cmux's default full
// path (e.g. "code/github.com/0x63616c/dotfiles" below "main").
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

VStack(alignment: .leading, spacing: 2) {
    ForEach(workspaces) { w in
        Button(action: { cmux("workspace.select", workspace_id: w.id) }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(basename(w.directory))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundColor(w.selected ? .primary : .secondary)
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
            .background(w.selected ? Color("#7f7f7f3d") : Color.clear)
            .cornerRadius(8)
        }
    }
}
