# ami — chat advisor panel (advice, not action)  [EXAMPLE]
#
# Demonstrates the ami-chat.nvim extension (https://github.com/moosch/ami-chat.nvim),
# loaded by demos/init.lua alongside ami core.
#
# Record with:  vhs demos/chat.tape   (needs `vhs` + a running LM Studio, and
# ami-chat.nvim checked out next to this repo).
#
# The advisor panel is right-docked and semi-transparent by default, so the
# source file stays visible (and shows faintly through the panel). This demo
# uses a file with a few long lines so that see-through effect is visible.
#
# Chat model defaults to qwen3-coder here (best advisor replies, usually already
# loaded); override with AMI_CHAT_MODEL. Lengthen the Sleep for slower models.

Output demos/chat.gif

Require nvim
Set Shell "bash"
Set FontSize 18
Set Width 1280
Set Height 760
Set Padding 20
Set Framerate 24
Set TypingSpeed 45ms
Set Theme "Catppuccin Mocha"

# --- setup (hidden): write a source file with some long lines to discuss ---
# \042 is printf's octal for a double quote (keeps literal quotes out of the
# VHS string); %% prints a literal % so Go's %q/%w survive printf.
Hide
Type "printf 'package store\n\nimport (\n\t\042context\042\n\t\042database/sql\042\n\t\042errors\042\n\t\042fmt\042\n)\n\nvar ErrNotFound = errors.New(\042store: user not found\042)\n\n// Get loads one user by id, returning ErrNotFound when the row is absent.\nfunc Get(ctx context.Context, db *sql.DB, id string) (*User, error) {\n\trow := db.QueryRowContext(ctx, \042SELECT id, name, email FROM users WHERE id = $1\042, id)\n\tvar u User\n\tif err := row.Scan(&u.ID, &u.Name, &u.Email); err != nil {\n\t\treturn nil, fmt.Errorf(\042store.Get(%%q): %%w\042, id, err)\n\t}\n\treturn &u, nil\n}\n' > /tmp/ami_chat_demo.go"
Enter
Type "AMI_CHAT_MODEL=${AMI_CHAT_MODEL:-qwen3-coder} nvim -u demos/init.lua /tmp/ami_chat_demo.go"
Enter
Sleep 5s           # let the daemon start and become ready
Show
Sleep 1500ms       # show the plain source pane first

# --- open the chat prompt and ask a question ---
Type ":AmiChat"
Enter
Sleep 2s           # the right-docked, see-through panel slides in over the code
Type "What edge cases should Get handle, and how would you structure the errors?"
Escape
Enter

# --- wait for the streamed advice ---
Sleep 20s
