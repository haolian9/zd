a tool to remember directories manually, to fuzzy match a directory manually.

## status
* just works
* feature-frozen

## aimed use environment
* linux
* zig 0.11     # for compilation
* haolian9/fzf # for --input-file option and char event

## setup
* `zig build -Doptimize=ReleaseFast`
* `zig build -Doptimize=ReleaseFast --prefix-exe-dir ~/bin`

## usage
* zd add {path}
* zd clear
* zd list
* zd tidy
* zd fzf        # equals to `cd $(zd list | fzf)`
* zd            # equals to `zd fzf`
* zd .          # equals to `zd add $(pwd)`

## todo
* [x] prevent duplicate entries
* [x] repeat last query - fzf
* [x] shell integration - alias: `alias z='eval $(zd fzf)'`
* [ ] ~~shell integration - keybind~~
* [x] prune not-existed entries
* [ ] ~~scoped database: project/git vs. global~~
* [ ] ~~weighted entries based on frenquency~~
* [ ] ~~discard entries~~
