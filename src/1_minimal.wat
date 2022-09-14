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

    ;; $alloc allocates a block of $size 32-bit words and returns the starting
    ;; address of the allocated block. If $size is zero, nothing is allocated
    ;; and zero is returned. The memory is grown if necessary.
    (func $alloc (export "alloc") (param $size i32) (result i32)
        ;; If the requested $size is zero, just return zero.
        (if ;; $size == 0
            (i32.eqz (local.get $size))
            ;; return 0
            (return (i32.const 0))
        )
        ;; Push $next to the stack so we can return it later.
        (global.get $next)
        ;; Increase $next by `$size * 4` bytes.
        (global.set $next
            (i32.add
                (global.get $next)
                (i32.mul                    
                    (local.get $size)
                    (i32.const 4)
                )
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
                (i32.add
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

    ;; $dealloc does nothing in this minimal implementation.
    (func $dealloc (export "dealloc") (param $address i32))

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
