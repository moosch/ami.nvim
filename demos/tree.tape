# ami — conversation tree (branch / summarize)
#
# Record with:  vhs demos/tree.tape   (needs `vhs` + a running LM Studio)
#
# This one has two chat turns (so the tree has nodes) before opening :AmiTree,
# then summarizes an early node. It is the most timing-sensitive tape:
#  - lengthen the Sleeps after each Enter to cover the streamed replies
#  - the `j` count and `s` assume the built-in layout; adjust if your nodes differ

Output demos/tree.gif

Require nvim
Set Shell "bash"
Set FontSize 17
Set Width 1300
Set Height 800
Set Padding 20
Set Framerate 24
Set TypingSpeed 45ms
Set Theme "Catppuccin Mocha"

# --- setup (hidden) ---
Hide
Type "printf 'package store\n\nfunc Get(id string) (*User, error) {\n\treturn db.lookup(id)\n}\n' > /tmp/ami_tree_demo.go"
Enter
Type "nvim -u demos/init.lua /tmp/ami_tree_demo.go"
Enter
Sleep 5s
Show
Sleep 1s

# --- turn 1 ---
Type ":AmiChat"
Enter
Sleep 1200ms
Type "What edge cases should Get handle?"
Escape
Enter
Sleep 18s

# --- turn 2 (prompt stays open after sending) ---
Type "i"
Type "And how would you name the error variables?"
Escape
Enter
Sleep 18s

# --- close the chat, open the tree ---
Type "q"
Sleep 800ms
Type ":AmiTree"
Enter
Sleep 1500ms

# --- focus the tree split and summarize up to the first assistant node ---
Ctrl+W
Type "l"
Sleep 800ms
Type "j"
Sleep 600ms
Type "s"
Sleep 13s
