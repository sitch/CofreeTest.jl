"""
    Cofree{F, A}

The cofree comonad over functor `F` with annotation type `A`.

Each node carries a `head::A` (the annotation) and a `tail::F` (children shaped by functor F).
For rose trees, `F = Vector{Cofree{Vector, A}}`.

# Comonad operations
- `extract(c)` — get the annotation at this node
- `duplicate(c)` — each node sees its full subtree
- `extend(f, c)` — apply f to each node-in-context

# Natural transformations
- `hoist(f, c)` — transform annotations preserving tree shape
- `fmap(f, children)` — map over child nodes

```jldoctest
julia> using CofreeTest

julia> leaf(42)
42

julia> suite(:root, [leaf(:a), leaf(:b)])
:root
├─ :a
└─ :b
```
"""
struct Cofree{F, A}
    head::A
    tail::F
end

# --- Display ---

function Base.show(io::IO, c::Cofree)
    print(io, "Cofree(")
    show(io, c.head)
    print(io, ", ")
    if c.tail isa AbstractVector
        print(io, "Cofree[")
        for (i, child) in enumerate(c.tail)
            i > 1 && print(io, ", ")
            show(io, child)
        end
        print(io, "]")
    else
        show(io, c.tail)
    end
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", c::Cofree)
    _print_tree(io, c, "", true, true)
end

function _print_tree(io::IO, c::Cofree, prefix::String, is_last::Bool, is_root::Bool)
    if !is_root
        print(io, prefix)
        print(io, is_last ? "└─ " : "├─ ")
    end
    show(io, c.head)
    children = c.tail
    if (children isa AbstractVector || children isa Tuple) && !isempty(children)
        child_prefix = is_root ? "" : prefix * (is_last ? "   " : "│  ")
        for (i, child) in enumerate(children)
            println(io)
            _print_tree(io, child, child_prefix, i == length(children), false)
        end
    end
end

"""
    extract(c::Cofree) -> A

Get the annotation at this node. The counit of the comonad.

```jldoctest
julia> using CofreeTest

julia> c = leaf(:hello)

julia> extract(c)
:hello
```
"""
extract(c::Cofree) = c.head

"""
    fmap(f, v::Vector) -> Vector

Map `f` over a Vector of children. This is the functor instance for Vector (rose trees).

```jldoctest
julia> using CofreeTest

julia> children = [leaf(1), leaf(2), leaf(3)]

julia> doubled = fmap(c -> hoist(x -> 2x, c), children)

julia> extract.(doubled)
3-element Vector{Int64}:
 2
 4
 6
```
"""
fmap(f, v::Vector) = map(f, v)

"""
    fmap(f, t::Tuple) -> Tuple

Map `f` over a Tuple of children. Functor instance for fixed-arity branching.
"""
fmap(f, t::Tuple) = map(f, t)

"""
    duplicate(c::Cofree) -> Cofree{F, Cofree{F, A}}

Each node sees its entire subtree. The comultiplication of the comonad.

```jldoctest
julia> using CofreeTest

julia> tree = suite(:root, [leaf(:a), leaf(:b)])

julia> d = duplicate(tree)

julia> extract(d) === tree
true

julia> extract(extract(d))
:root

julia> extract.(extract.(d.tail))
2-element Vector{Symbol}:
 :a
 :b
```
"""
duplicate(c::Cofree) = Cofree(c, fmap(duplicate, c.tail))

"""
    extend(f, c::Cofree) -> Cofree

Apply `f` to each node-in-context. The coKleisli extension.
`f` receives a `Cofree` (the node plus its entire subtree) and returns a new annotation.

```jldoctest
julia> using CofreeTest

julia> tree = suite(1, [leaf(10), leaf(20)])

julia> sums = extend(c -> sum(extract.(c.tail); init=extract(c)), tree)

julia> extract(sums)
31

julia> extract.(sums.tail)
2-element Vector{Int64}:
 10
 20
```
"""
extend(f, c::Cofree) = Cofree(f(c), fmap(w -> extend(f, w), c.tail))

"""
    hoist(f, c::Cofree) -> Cofree

Natural transformation: transform annotations while preserving tree structure.
`f` is applied to each `head` value.

```jldoctest
julia> using CofreeTest

julia> tree = suite(1, [leaf(2), leaf(3)])

julia> doubled = hoist(x -> 2x, tree)

julia> extract(doubled)
2

julia> extract.(doubled.tail)
2-element Vector{Int64}:
 4
 6
```
"""
hoist(f, c::Cofree) = Cofree(f(c.head), fmap(child -> hoist(f, child), c.tail))

"""
    leaf(a) -> Cofree

Create a leaf node (no children) with annotation `a`.

```jldoctest
julia> using CofreeTest

julia> node = leaf(42)

julia> extract(node)
42

julia> isempty(node.tail)
true
```
"""
leaf(a) = Cofree(a, Cofree[])

"""
    suite(a, children::Vector) -> Cofree

Create a suite node with annotation `a` and child nodes.

```jldoctest
julia> using CofreeTest

julia> tree = suite(:root, [leaf(:a), leaf(:b)])

julia> extract(tree)
:root

julia> length(tree.tail)
2

julia> extract.(tree.tail)
2-element Vector{Symbol}:
 :a
 :b
```
"""
suite(a, children::Vector) = Cofree(a, children)
