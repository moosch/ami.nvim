# ami — chat advisor panel (advice, not action)
#
# Record with:  vhs demos/chat.tape   (needs `vhs` + a running LM Studio)
#
# The Sleep after sending must cover the streamed reply; lengthen it for slower
# models.

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

# --- setup (hidden): open a small source file to discuss ---
Hide
Type "printf 'package store\n\nfunc Get(id string) (*User, error) {\n\treturn db.lookup(id)\n}\n' > /tmp/ami_chat_demo.go"
Enter
Type "nvim -u demos/init.lua /tmp/ami_chat_demo.go"
Enter
Sleep 5s           # let the daemon start and become ready
Show
Sleep 1s

# --- open the chat prompt and ask a question ---
Type ":AmiChat"
Enter
Sleep 1500ms
Type "What edge cases should Get handle, and how would you structure the errors?"
Escape
Enter

# --- wait for the streamed advice (first token ~5s + streaming) ---
Sleep 22s
