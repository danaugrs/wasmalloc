;; 1_minimal.wat
;;
;; A minimal implementation of a dynamic memory allocator in WebAssembly.
;;
;; It's the fastest in allocation and deallocation speed, but it's extremely
;; unoptimal in terms of memory usage - it never deallocates.
(module
    ;; An empty memory.
    (memory 0)

    ;; $next is the address to be returned in the next call to $alloc.
    ;; It's the start of the free memory area. It increases whenever $alloc
    ;; is called with a non-zero argument, and it never decreases.
    (global $next (mut i32) (i32.const 0))

    ;; $alloc allocates a block of memory of the specified size.
    ;; If $size is zero, nothing is allocated and zero is returned.
    ;; The memory is grown if necessary.
    (func $alloc (export "alloc")
        (param $size i32) ;; size of the requested block in bytes
        (result i32) ;; address of the allocated block

        ;; If the requested $size is zero, just return zero.
        (if ;; $size == 0
            (i32.eqz (local.get $size))
            (return (i32.const 0)) ;; return 0
        )

        ;; Push $next to the stack so we can return it later.
        (global.get $next)

        ;; Increase $next by `$size` bytes.
        (global.set $next
            (i32.add
                (global.get $next)
                (local.get $size)
            )
        )

        ;; Grow the memory by `($next / 65536) + 1 - memory.size`.
        ;; The expression will result in zero if we don't need to grow the
        ;; memory, otherwise it will result in the number of pages to grow by.
        ;; If the newly allocated block ends at a page boundary (when the
        ;; remainder of `$next / 65536` is zero) we technically wouldn't need
        ;; to grow the memory, but it will be grown nonetheless.
        (drop
            (memory.grow
                (i32.add ;; ($next / 65536) + 1 - memory.size
                    (i32.div_u
                        (global.get $next)
                        (i32.const 65536)
                    )
                    (i32.sub
                        ;; Instead of a hardcoded 1 below, the "right" thing to
                        ;; do would be to check if `$next/65536` has a non-zero
                        ;; remainder and use 1 if so, and 0 otherwise:
                        ;;
                        ;;     ;; $next % 65536 > 0
                        ;;     (i32.gt_u
                        ;;         (i32.rem_u
                        ;;             (global.get $next)
                        ;;             (i32.const 65536)
                        ;;         )
                        ;;         (i32.const 0)
                        ;;     )
                        ;;
                        ;; However, hardcoding a 1 here simplifies the logic.
                        ;; The only resulting change is that if the newly
                        ;; allocated block ends exactly at a page boundary
                        ;; we eagerly grow the memory by one more page instead
                        ;; of waiting to do it in the next allocation. This
                        ;; probably brings more benefits in more situations
                        ;; than not. For example, when growing the memory,
                        ;; it's possible that the runtime will make a call
                        ;; to the operating system for more memory, which can
                        ;; be slow. If we do it eagerly, before we actually
                        ;; need to use the memory, we might save some time.
                        (i32.const 1)
                        (memory.size)
                    )
                )
            )
        )
        ;; Return the original $next (which is left in the stack).
    )

    ;; $dealloc deallocates a previously allocated block.
    ;; It does nothing in this minimal implementation.
    (func $dealloc (export "dealloc")
        (param $address i32) ;; address of the block to deallocate
    )

    ;; $realloc reallocates a previously allocated block with a new size.
    ;; In this minimal implementation it simply allocates a new block and copies
    ;; the data from the old one into the new.
    (func $realloc (export "realloc")
        (param $address i32) ;; address of the previously allocated block
        (param $size i32) ;; new size of the block in bytes
        (result i32) ;; address of the newly allocated block

        (local $new i32) ;; the address of the newly allocated block

        ;; Copy the contents of the old block to a new block.
        (memory.copy
            ;; The destination is the address of a new block that we allocate by
            ;; calling $alloc. We store the new block's address in $new.
            (local.tee $new (call $alloc (local.get $size)))
            ;; The source is the address of the original block.
            (local.get $address)
            ;; Since we don't know the size of the original block, the number of
            ;; bytes we'll copy is just $size.
            (local.get $size)
        )

        ;; Return the address of the new block.
        (return (local.get $new))
    )

    ;; Auxiliary functions for testing.
    (func $store (export "store") (param $address i32) (param $value i32)
        (i32.store (local.get $address) (local.get $value))
    )
    (func $load (export "load") (param $address i32) (result i32)
        (i32.load (local.get $address))
    )
    (func $size (export "size") (result i32)
        (memory.size)
    )
    (func $grow (export "grow") (param $s i32) (result i32)
        (memory.grow (local.get $s))
    )
)
