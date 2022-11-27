# Nvim : jump to mark

## Idea

For a long time... I wanted a nvim workflow with mulitple windows and tab opened, to form a mental map about the code, using visual assistence (tabs, and windows).
I tried seraching over the internet, using plugins, and something was still missing : jumping through windows, to the exact line bookmarked.

## Requirements

Due to workflow, this code requires the following plugins installed (and their requirements):

* nvim-marks : Local marks in files, and create a Quickfix list based on these marks
* fzf-lua : Prefered option for fuzzy finding. The code uses the plugin api, to apply function on result (jumping to window, then jump to line)

## Instructions

* Grab some local Marks on opened files, and create tabs with other files or marks
* Run command '`:MarksQFListAll`', to generate a list of Quickfix for local marks (using Marks.nvim plugin)
* Then, run the following code of repo (`:luafile ~/Repositories/nvim-jump-to-mark/nvim-jump-to-mark.lua`), to open fzf-lua window, and see all of your local marks by file, with previewer included!
* Press Enter, on result, to jump to mark in the first corresponding window

## TODO

For now... this is one night/morning code, for making my life easier the following week. So, there is a lot of imrpovement to do. Some of them:
* Include the creation of Quickfix list, without using `:MarksQFListAll`
* Better appearance of resutls (its for now... very ugly, copy pasted... but functional)
* Refactor, and clean code (there its a lot unused... because its a copy paste of fzf-lua tabs code)
* Change the "Tabs" title (yes.. I Copied tabs of fzf-lua, then... modifying results list)
