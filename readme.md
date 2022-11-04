## prerequisites
* linux
* zig 0.10     # for compilation
* haolian9/fzf # for --input-file option

## setup
* `zig build -Dreleas-safe`

## usage
* zd add {path}
* zd clear
* zd list
* zd fzf        # equals to `zd list | fzf`
* zd fzy        # equals to `zd list | fzy`
* zd            # equals to `zd fzf`
* zd .          # equals to `zd add $(pwd)`

## todo
* [x] prevent duplicate entries
* [ ] repeat last query
* [x] shell integration - alias: `alias z='eval $(zd fzf)'`
* [ ] shell integration - keybind
* [x] integrate fzy
* [ ] complation tag for fzf and fzy
* [ ] prune not-existed entries
* [ ] scoped database: project/git vs. global
* [ ] ~~weighted entries based on frenquency~~
* [ ] ~~discard entries~~
