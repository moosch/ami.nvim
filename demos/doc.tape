# ami — generate a document into the repo  [EXAMPLE]
#
# Demonstrates the ami-doc.nvim extension (https://github.com/moosch/ami-doc.nvim),
# loaded by demos/init.lua alongside ami core + ami-chat when AMI_DEMO_DOC=1.
#
# ami's advisor never writes files; ami-doc is the opt-in that lets you ask for one.
# Here we open an X11 stub, then /doc a complete annotated EXAMPLE.md next to it —
# ami writes the file (in the project root) and opens it in a split.
#
# Record with:  vhs demos/doc.tape   (needs `vhs` + a running LM Studio, with
# ami-chat.nvim and ami-doc.nvim checked out next to this repo).
#
# Doc model defaults to qwen3-coder; override with AMI_CHAT_MODEL. Point ami at a
# non-localhost server with AMI_ENDPOINT. Lengthen the final Sleep for slower models.

Output demos/doc.gif

Require nvim
Set Shell "bash"
Set FontSize 18
Set Width 1280
Set Height 760
Set Padding 20
Set Framerate 24
Set TypingSpeed 45ms
Set Theme "Catppuccin Mocha"

# --- setup (hidden): a fresh temp project with an X11 stub to flesh out ---
Hide
Type "mkdir -p /tmp/ami_doc_demo && : > /tmp/ami_doc_demo/README.md && rm -f /tmp/ami_doc_demo/EXAMPLE.md"
Enter
Type "printf '// main.c \342\200\224 opening a window with X11.\n#include <X11/Xlib.h>\n\nint main(void) {\n    // TODO: open a display, create a window, and run the event loop.\n    return 0;\n}\n' > /tmp/ami_doc_demo/main.c"
Enter
Type "AMI_DEMO_DOC=1 AMI_CHAT_MODEL=${AMI_CHAT_MODEL:-qwen3-coder} nvim -u demos/init.lua /tmp/ami_doc_demo/main.c"
Enter
Sleep 2s           # let the editor settle
Show
Sleep 1500ms       # show the X11 stub first

# --- open chat and ask ami to write a short annotated doc ---
Type ":AmiChat"
Enter
Sleep 2s           # the right-docked panel slides in
Type "/doc EXAMPLE.md a minimal annotated example of opening a window with X11 in C: one code block and a short explanation of each step"
Escape
Enter

# --- ami writes EXAMPLE.md in the project root and opens it in a split ---
# The static "writing…" stretch is trimmed out of the committed GIF (see the repo's
# demos notes); a full `vhs` render waits the whole generation time here.
Sleep 2s           # "writing EXAMPLE.md…"
Sleep 22s          # generation, then the written file opens beside the stub
