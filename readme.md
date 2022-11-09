
provides a tool to remember directories manually, to fuzzy match a directory manually.

## status: just-works
* it requires my personal flavor of fzf

## aimed use environment
* linux
* zig 0.10     # for compilation
* haolian9/fzf # for --input-file option and char event

## setup
* choose one fuzzy matcher: `-Dfzf` or `-Dfzy`, say it's `-Dfzf`
* `zig build -Dreleas-safe -Dfzf`

## usage
* zd add {path}
* zd clear
* zd list
* zd tidy
* zd fzf        # equals to `cd $(zd list | fzf)`
* zd fzy        # equals to `cd $(zd list | fzy)`
* zd            # equals to `zd fzf` or `zd fzy`
* zd .          # equals to `zd add $(pwd)`

## todo
* [x] prevent duplicate entries
* [x] repeat last query - fzf
* [x] shell integration - alias: `alias z='eval $(zd fzf)'`
* [ ] shell integration - keybind
* [x] integrate fzy
* [x] complation tag for fzf and fzy
* [x] prune not-existed entries
* [ ] ~~scoped database: project/git vs. global~~
* [ ] ~~weighted entries based on frenquency~~
* [ ] ~~discard entries~~
* [ ] ~~customize fzy - repeat last query~~
* [ ] customize fzy - query as placeholder

## special thanks
* [fzy.zig](https://github.com/gpanders/fzy.zig)
