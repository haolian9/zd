## prerequisites
* linux
* zig 0.10
* haolian9/fzf # for --input-file option

## setup
* `zig build -Dreleas-safe`
* `alias z='eval $(/path/to/zd/zig-out/bin/zd)'`

## usage
* zd [fzf]
* zd add|. [path]
* zd clear
* zd list

## todo
* prevent duplicate entries
* weighted entries based on frenquency
* prune not-existed entries
* ~~shell integration~~
* placeholder of fzf --query
* replace fzf with fzy
* scoped database
    * project, git root
    * global
