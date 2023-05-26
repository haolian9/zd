a tool to remember directories manually, to fuzzy match a directory manually.

## status: just-works
* it requires my personal flavor of fzf

## aimed use environment
* linux
* zig 0.10     # for compilation
* haolian9/fzf # for --input-file option and char event

## setup
* `zig build -Drelease-safe -Dfzf`

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
