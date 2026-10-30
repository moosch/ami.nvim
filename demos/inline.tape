# ami — inline (FIM) comment-driven completion
#
# Record with:  vhs demos/inline.tape   (needs `vhs` + a running LM Studio)
# Set AMI_ENDPOINT etc. in your shell first if LM Studio isn't on localhost.
#
# Tune the Sleep after Ctrl+G to your model's latency — it must cover the time
# from trigger to ghost text appearing.

Output demos/inline.gif

Require nvim
Set Shell "bash"
Set FontSize 18
Set Width 1200
Set Height 720
Set Padding 20
Set Framerate 24
Set TypingSpeed 55ms
Set Theme "Catppuccin Mocha"

# --- setup (hidden): open an empty Go buffer with the demo config ---
Hide
Type "nvim -u demos/init.lua /tmp/ami_inline_demo.go"
Enter
Sleep 3s
Show

# --- write a comment describing what we want ---
Type "i"
Type "package server"
Enter
Enter
Type "// Function to switch over HTTP methods and dispatch to handlers"
Enter
Sleep 1s

# --- request a completion; wait for the ghost text ---
Ctrl+G
Sleep 6s

# --- accept it ---
Tab
Sleep 2s
Escape
Sleep 2500ms
