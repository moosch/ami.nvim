# ami — conversation tree: BRANCHING
#
# Record with:  vhs demos/tree-branch.tape   (needs `vhs` + a running LM Studio)
#
# Shows a real fork: two short exchanges, then branch at an assistant node and
# send a different follow-up, so that node ends up with two children.
#
# Prompts ask for one-sentence answers to keep the replies (and the GIF) short.
# This is the most timing-sensitive tape — tune every Sleep that follows an Enter
# to cover the streamed reply, and adjust the `j`/<CR> if your node layout differs.

Output demos/tree-branch.gif

Require nvim
Set Shell "bash"
Set FontSize 17
Set Width 1300
Set Height 820
Set Padding 20
Set Framerate 24
Set TypingSpeed 45ms
Set Theme "Catppuccin Mocha"

# --- setup (hidden) ---
Hide
Type "printf 'package store\n\nfunc Get(id string) (*User, error) {\n\treturn db.lookup(id)\n}\n' > /tmp/ami_branch_demo.go"
Enter
Type "nvim -u demos/init.lua /tmp/ami_branch_demo.go"
Enter
Sleep 3s
Show
Sleep 1s

# --- turn 1 ---
Type ":AmiChat"
Enter
Sleep 1200ms
Type "In one sentence, what does Get do?"
Escape
Enter
Sleep 8s

# --- turn 2 (prompt stays open) : history is now n1,n2,n3,n4 ---
Type "i"
Type "In one sentence, suggest a clearer name for it."
Escape
Enter
Sleep 8s

# --- close chat, open the tree, focus it ---
Type "q"
Sleep 800ms
Type ":AmiTree"
Enter
Sleep 1200ms
Ctrl+W
Type "l"
Sleep 600ms

# --- branch at the first assistant node (line 2) ---
Type "j"
Sleep 500ms
Enter
Sleep 2500ms

# --- close the tree (focus returns to the code buffer) ---
Type "q"
Sleep 600ms

# --- send a DIFFERENT follow-up: this forks the branch at that node ---
Type ":AmiChat"
Enter
Sleep 1000ms
Type "In one sentence, should Get cache results instead?"
Escape
Enter
Sleep 8s

# --- reopen the tree to reveal the fork ---
Type "q"
Sleep 800ms
Type ":AmiTree"
Enter
Sleep 1200ms
Ctrl+W
Type "l"
Sleep 3s
