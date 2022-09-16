# wasmalloc

This repository contains a collection of hand-written and well-commented dynamic memory allocators for [WebAssembly](https://webassembly.org/).

The goal is to build several implementations of increasing complexity building up to `wasmalloc`, which will be a general-purpose dynamic memory allocator built for [Flame](https://flame.run).

| Implementation                                | Description                               | Space-complexity | Time-complexity |
| --------------------------------------------- | ----------------------------------------- | ---------------  | --------------- |
| [1_minimal.wat](src/1_minimal.wat)            | Minimal allocator that never deallocates. | Terrible         | Best            |
| [2_linked.wat](src/2_linked.wat) (TODO)       | Uses a linked list of blocks.             | Best             | Terrible        |
| [3_doubly.wat](src/3_doubly.wat) (TODO)       | Uses a doubly-linked list of blocks.      | Good             | Medium          |
| [4_bins.wat](src/4_bins.wat) (TODO)           | Uses binning.                             | Good             | Good            |
| [5_wasmalloc.wat](src/5_wasmalloc.wat) (TODO) | Uses complex optimizations.               | Great            | Great           |

All implementations will be extensively commented and follow the same three-function interface:

```wasm
;; $alloc allocates a block of memory of the specified size.
(func $alloc (export "alloc")
    (param $size i32) ;; size of the requested block (number of 32-bit words).
    (result i32) ;; starting address of the allocated block.
    ...
)

;; $realloc reallocates a previously allocated block with a new size.
(func $realloc (export "dealloc")
    (param $address i32) ;; starting address of the previously allocated block.
    (param $size i32) ;; new size of the block (number of 32-bit words).
    (result i32)
    ...
)

;; `dealloc` deallocates a previously allocated block.
(func $dealloc (export "dealloc")
    (param $address i32) ;; starting address of the block to deallocate.
    ...
)
```
