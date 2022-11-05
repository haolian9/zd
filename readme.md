## prerequisites
* linux
* zig 0.10     # for compilation
* haolian9/fzf # for --input-file option

## setup
* `zig build -Dreleas-safe`
* to opt-in fzf support, add `-Dfzf`
* to opt-in fzy support, add `-Dfzy`

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
* [ ] ~~repeat last query - fzy~~
