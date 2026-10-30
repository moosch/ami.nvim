# ami — runtime model selector (:AmiModel)
#
# Record with:  vhs demos/model.tape   (needs `vhs` + a running LM Studio)
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
Set TypingSpeed 60ms
Set Theme "Catppuccin Mocha"

# --- setup (hidden) ---
Hide
Type "nvim -u demos/init.lua /tmp/ami_model_demo.go"
Enter
Sleep 3s
Show
Sleep 1s

# --- open the selector: choose a target (1 = chat), then a model ---
Type ":AmiModel"
Enter
Sleep 1500ms
Type "1"
Enter
Sleep 2500ms      # fetch the model list from the provider

# pick a model by number (the current one is marked ●) — adjust to taste
Type "2"
Enter
Sleep 3s          # shows the "ami: chat model → <name>" notification
