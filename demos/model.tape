# ami — runtime model registry / selector (:AmiModel)  [EXAMPLE]
#
# The selector is core, but the slots it lists come from extensions: this demo
# loads ami-chat.nvim (https://github.com/moosch/ami-chat.nvim) and ami-inline.nvim
# (https://github.com/moosch/ami-inline.nvim) via demos/init.lua, so it shows the
# default / chat / fim slots.
#
# Record with:  vhs demos/model.tape   (needs `vhs` + a running LM Studio, and
# those extension repos checked out next to this one).
#
# Uses Neovim's built-in vim.ui.select (the demo config has no picker plugin),
# which is a numbered inputlist: type a number, press Enter. If you use
# telescope/fzf/snacks, the interaction differs — adjust the keystrokes.

Output demos/model.gif

Require nvim
Set Shell "bash"
Set FontSize 18
Set Width 1200
Set Height 700
Set Padding 20
Set Framerate 24
Set TypingSpeed 60ms
Set Theme "Catppuccin Mocha"

# --- setup (hidden): write the shared source file and open it as a backdrop ---
# \042 is printf's octal for a double quote; %% prints a literal %.
Hide
Type "printf 'package store\n\nimport (\n\t\042context\042\n\t\042database/sql\042\n\t\042errors\042\n\t\042fmt\042\n)\n\nvar ErrNotFound = errors.New(\042store: user not found\042)\n\n// Get loads one user by id, returning ErrNotFound when the row is absent.\nfunc Get(ctx context.Context, db *sql.DB, id string) (*User, error) {\n\trow := db.QueryRowContext(ctx, \042SELECT id, name, email FROM users WHERE id = $1\042, id)\n\tvar u User\n\tif err := row.Scan(&u.ID, &u.Name, &u.Email); err != nil {\n\t\treturn nil, fmt.Errorf(\042store.Get(%%q): %%w\042, id, err)\n\t}\n\treturn &u, nil\n}\n' > /tmp/ami_model_demo.go"
Enter
Type "nvim -u demos/init.lua /tmp/ami_model_demo.go"
Enter
Sleep 3s
Show
Sleep 1s

# --- open the selector: choose a slot, then a model ---
# Slots are listed in registration order: 1=default, 2=chat, 3=fim. Pick chat (2).
Type ":AmiModel"
Enter
Sleep 1500ms
Type "2"
Enter
Sleep 2500ms      # fetch the model list from the slot's provider

# pick a model by number (the current one is marked ●) — adjust to taste
Type "2"
Enter
Sleep 3s          # shows the "ami: chat model → <name>" notification
