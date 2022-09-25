;; 2_linked.wat
;;
;; A dynamic memory allocator that is a first-order improvement over
;; 1_minimal.wat. It uses a memory-sorted linked list to keep track of free
;; blocks and it chooses blocks using a first-fit algorithm.
;;
;; It's better than 1_minimal.wat in terms of memory usage but it's extremely
;; unoptimal in terms of allocation and deallocation speed since it needs to
;; search the free list block by block, sometimes in its entirety.
;;
;; Each block has a header with the block size (in 32-bit words) and a pointer
;; to the next block. A block only needs a next-block pointer when it's free.
;; Therefore we can use that space for data when the block is in use.
;;
;;   used block   free block
;;  ┌──────────┐ ┌──────────┐
;;  │block size│ │block size│
;;  ├──────────┤ ├──────────┤◄─── address of the block
;;  │          │ │next block│
;;  │          │ ├──────────┤
;;  │          │ │          │
;;  │   data   │ │          │
;;  │          │ │  empty   │
;;  │          │ │          │
;;  │          │ │          │
;;  └──────────┘ └──────────┘
;;
(module
    ;; A 1-page memory. One page is 64KiB = 65536 bytes.
    (memory 1)

    ;; Initialize the first two 32-bit words in memory to be the header of a
    ;; free block that spans the entire memory. The first 32-bit word is the
    ;; size of the block, which is the page-size minus these 4 bytes which are
    ;; the block header.
    (data (i32.const 0) "\FC\FF\00\00") ;; 65532
    ;; The second 32-bit word is the next-block pointer, and it's set to zero
    ;; to indicate that this is the last (only) block in the list.
    (data (i32.const 4) "\00\00\00\00") ;; 0

    ;; $free is the address of the first block in the free list. It's starts set
    ;; to four as that's the address of the initial whole-memory block.
    (global $free (mut i32) (i32.const 4))

    ;; $max_extra is the configurable maximum extra space allowed in blocks.
    ;; We only split blocks whose size is greater than $size + $max_extra.
    ;; This effectively allows trading-off internal and external fragmentation.
    ;; Decreasing $max_extra will cause blocks to be split more frequently,
    ;; resulting in lower internal fragmentation but leading to greater external
    ;; fragmentation. Increasing $max_extra, on the other hand, will cause
    ;; blocks to be split less frequently, resulting in greater internal
    ;; fragmentation but lower external fragmentation. The minimum value that
    ;; results in a useful post-split block is 2 (32-bit) words. The default is
    ;; 4 words, which means that only blocks which exceed $size by 5 words or
    ;; more will be split, resulting in a post-split block of at least 4 words.
    (global $max_extra (mut i32) (i32.const 4))

    ;; $alloc allocates a block of memory of the specified size.
    ;; If $size is zero, nothing is allocated and zero is returned.
    ;; The memory is grown if necessary.
    (func $alloc (export "alloc")
        (param $size i32) ;; size of the requested block (in 32-bit words)
        (result i32) ;; address of the allocated block

        ;; Three locals that we'll use.
        (local $prev i32) ;; the address of the previous block in the free list
        (local $curr i32) ;; the address of current block in the free list
        (local $temp i32) ;; temporary value

        ;; If the requested $size is zero, just return zero.
        (if ;; $size == 0
            (i32.eqz (local.get $size))
            (return (i32.const 0)) ;; return 0
        )

        ;; Initialize $curr = $free.
        (local.set $curr (global.get $free))

        ;; Traverse the linked list of free blocks until we find a block that
        ;; satisfies the requested size. If we don't find a block that satisfies
        ;; the requested size we'll grow the memory and create a new block.
        ;; Either way, at the end of the loop $curr will point to a block that
        ;; we can use.
        (loop $loop

            ;; Break the loop if the size of the current block is sufficient.
            (br_if $loop ;; sizeOf($curr) >= $size
                (i32.ge_s
                    (i32.load ;; sizeOf($curr)
                        (i32.sub
                            (local.get $curr)
                            (i32.const 4)
                        )
                    )
                    (local.get $size)
                )
            )

            ;; Set $prev to $curr (the last free block in the free list)
            ;; before we overwrite $curr to point to the next block.
            (local.set $prev (local.get $curr))

            ;; Check if this is the last element in the free list. This is the
            ;; case if its next-block pointer is zero. The condition also sets
            ;; $curr to the next block in prepararation for the next loop
            ;; iteration.
            (if ;; next($curr) == 0
                (i32.eqz
                    ;; Get the address of the next block, store it in $curr,
                    ;; and also push it to the stack via `local.tee` so it can
                    ;; be used immediately by the `i32.eqz` instruction.
                    (local.tee $curr
                        (i32.load (local.get $curr))
                    )
                )
                (then
                    ;; This is the last block, which means no block exists in
                    ;; the free list that satisfies $size. Therefore we need to
                    ;; grow the memory by at least one page.

                    ;; Below we grow the memory by 1 + (4 * $size + 4) / 65536
                    ;; which simplifies to 1 + ($size + 1) / 16384 and set
                    ;; $curr = 4 + (page size) * (old memory size), which is the
                    ;; start of the newly grown area. We also repurpose $temp
                    ;; and set it to the newly grown size (in number of pages).
                    ;; We also push it to the stack via `local.tee` so it can be
                    ;; used immediately by `memory.grow`.
                    (local.set $curr
                        (i32.add ;; 4 + (page size) * (old memory size)
                            (i32.const 4) ;; header
                            (i32.mul ;; address of new page(s)
                                (i32.const 65536) ;; page size
                                (memory.grow ;; old memory size
                                    (local.tee $temp
                                        (i32.add ;; 1 + ($size + 1) / 16384
                                            (i32.const 1) ;; at least one page
                                            (i32.div_u
                                                (i32.add
                                                    (local.get $size)
                                                    (i32.const 1) ;; header
                                                )
                                                (i32.const 16384)
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    )

                    ;; We need to set up the newly grown page(s) as a free block
                    ;; and insert it at the end of the free list. But first we
                    ;; check if the previous block was free, and if so, we
                    ;; combine them both into one larger free block. To do that
                    ;; we check if the block pointed at by $prev is indeed the
                    ;; immediately preceding block. If not, it means there is a
                    ;; non-free block (not part of the free list) between $prev
                    ;; and $curr. We can do that by adding the size of $prev to
                    ;; its address plus 4 bytes of header and then check if
                    ;; that matches the address of $curr.
                    (if
                        (i32.eq ;; $curr == $prev + sizeOf($prev) + 4
                            (local.get $curr)
                            (i32.add
                                (local.get $prev)
                                (i32.add
                                    (i32.load ;; sizeOf($prev)
                                        (i32.sub
                                            (local.get $prev)
                                            (i32.const 4)
                                        )
                                    )
                                    (i32.const 4) ;; header
                                )
                            )
                        )
                        ;; Note: it's probably posible to optimize the
                        ;; "then-else" blocks below by introducing a local or
                        ;; reusing an existing one.
                        (then
                            ;; The previous block is free, so lets combine it
                            ;; with the newly grown memory area. To do that we
                            ;; can simply update the size of the previous block.
                            (i32.store
                                (i32.sub ;; address of previous block's size
                                    (local.get $prev)
                                    (i32.const 4)
                                )
                                (i32.add ;; sizeOf($prev) + (newly grown size)
                                    (i32.load ;; sizeOf($prev)
                                        (i32.sub
                                            (local.get $prev)
                                            (i32.const 4)
                                        )
                                    )
                                    (i32.mul ;; newly grown size
                                        (local.get $temp) ;; newly grown page(s)
                                        (i32.const 65536) ;; page size
                                    )
                                )
                            )

                            ;; Set $curr = $prev.
                            (local.set $curr (local.get $prev))
                        )
                        (else
                            ;; The previous block isn't free so we'll set up the
                            ;; newly grown memory area as a free block. First
                            ;; we'll set its block size in its header.
                            (i32.store
                                (i32.sub ;; address of new block's size
                                    (local.get $curr)
                                    (i32.const 4)
                                )
                                (i32.mul ;; newly grown size
                                    (local.get $temp) ;; newly grown page(s)
                                    (i32.const 65536) ;; page size
                                )
                            )

                            ;; Then we'll set its next-block pointer to zero to
                            ;; indicate that it's the last block.
                            (i32.store
                                (local.get $curr)
                                (i32.const 0) ;; zero indicates end of list
                            )

                            ;; Then we set the previous block's next-block
                            ;; pointer to point to this block.
                            (i32.store
                                (local.get $prev)
                                (local.get $curr) ;; address of this block
                            )
                        )
                    )

                    ;; End the loop. At this point $curr points to a free block
                    ;; that comprises at least the entire newly grown area of
                    ;; memory and, more importantly, that satisfies $size.
                    (br $loop)
                )
            )
        )

        ;; At this point $curr points to a free block that satisfies $size.
        ;; If the block is too large, we'll split it in two. This uses the
        ;; global configurable parameter $max_extra.
        (if
            (i32.gt_s ;; sizeOf($curr) > $size + $max_extra
                (i32.load ;; sizeOf($curr)
                    (i32.sub
                        (local.get $curr)
                        (i32.const 4)
                    )
                )
                (i32.add ;; $size + $max_extra
                    (local.get $size)
                    (global.get $max_extra)
                )
            )
            (then
                ;; The block is too large, let's split it in two. We'll keep the
                ;; first resulting block free since its next-block pointer
                ;; already correctly points to the next free block, and we'll
                ;; return the second resulting block.

                ;; Update the size of the first block and also store it into
                ;; $temp via `local.tee`.
                (i32.store
                    (i32.sub ;; address of the first split block's size
                        (local.get $curr)
                        (i32.const 4)
                    )
                    (local.tee $temp
                        (i32.sub ;; sizeOf($curr) - $size
                            (i32.load ;; sizeOf($curr)
                                (i32.sub
                                    (local.get $curr)
                                    (i32.const 4)
                                )
                            )
                            (local.get $size)
                        )
                    )
                )

                ;; Update $curr to point to the address of the second block.
                (local.set $curr ;; $curr = $curr + (sizeOf($curr) - $size)
                    (i32.add
                        (local.get $curr)
                        (local.get $temp) ;; sizeOf($curr) - $size
                    )
                )

                ;; Set the size of the second block in its header.
                (i32.store
                    (i32.sub ;; address of the second split block's size
                        (local.get $curr)
                        (i32.const 4)
                    )
                    (local.get $size) ;; size of the the newly split block
                )
            )
            (else
                ;; The block is not too large, so we can just return it to the
                ;; caller as is. But first we need to remove it from the free
                ;; list.

                ;; Update the previous block's next-block pointer to point to
                ;; the block after the current one, effectively skipping over
                ;; the current block. If $curr is the last block, then this will
                ;; set the previous block's next-block pointer to zero, which
                ;; will correctly indicate that it's the last block in the list.
                (i32.store
                    (local.get $prev)
                    (i32.load (local.get $curr))
                )
            )
        )

        ;; Return the block's address.
        (return (local.get $curr))
    )

    ;; $dealloc deallocates a previously allocated block.
    (func $dealloc (export "dealloc")
        (param $address i32) ;; address of the block to deallocate

        ;; Two locals that we'll use.
        (local $prev i32) ;; the address of the previous block in the free list
        (local $curr i32) ;; the address of current block in the free list

        ;; We need to search the free list for the correct, memory-sorted place
        ;; to insert this block.

        ;; Initialize $prev = 0.
        (local.set $prev (i32.const 0))

        ;; Initialize $curr = $free.
        (local.set $curr (global.get $free))

        ;; Traverse the linked list of free blocks until we find a block whose
        ;; address is greater than the address of the block we want to
        ;; deallocate. At the end of the loop $prev will either point to the
        ;; block before the one we want to deallocate, or, if the block to
        ;; deallocate is located before the first free block, $prev will remain
        ;; zero. If the block to deallocate is the last block, we won't find a
        ;; block whose adddress is greater and the loop will end with $prev
        ;; pointing to the last free block in the free list.
        (loop $loop

            ;; Break the loop if $curr > $address.
            (br_if $loop ;; $curr > $address
                (i32.gt_s
                    (local.get $curr)
                    (local.get $address)
                )
            )

            ;; Set $prev to $curr.
            (local.set $prev (local.get $curr))

            ;; Set $curr to the next block in the free list.
            (local.set $curr (i32.load (local.get $curr)))
        )

        ;; At this point $prev is either zero or it's the address of the block
        ;; before the one we want to deallocate.

        ;; If $prev is zero, we need to insert the block we are deallocating at
        ;; the beginning of the free list. Otherwise, we insert it after $prev.
        (if ;; $prev == 0
            (i32.eqz (local.get $prev))
            (then
                ;; The block we are deallocating is located in memory before the
                ;; very first free block in the free list.

                ;; Set the block's next-block pointer to $free.
                (i32.store
                    (local.get $address)
                    (global.get $free)
                )

                ;; Set $free to point to this block.
                (global.set $free (local.get $address))
            )
            (else
                ;; $prev is the address of the free block that precedes the
                ;; block we are deallocating.

                ;; Set the block's next-block pointer to $prev's next-block.
                (i32.store
                    (local.get $address)
                    (i32.load (local.get $prev))
                )

                ;; Set $prev's next-block pointer to point to this block.
                (i32.store
                    (local.get $prev)
                    (local.get $address)
                )
            )
        )

        ;; TODO: check if neighboring blocks are free and coalesce if so.
    )

    ;; $realloc reallocates a previously allocated block with a new size.
    (func $realloc (export "realloc")
        (param $address i32) ;; address of the previously allocated block
        (param $size i32) ;; new size of the block (in 32-bit words)
        (result i32) ;; address of the newly allocated block

        (local $new i32) ;; the address of the newly allocated block

        ;; If the requested size is smaller than the current block size we can
        ;; just return the current block. Note that the current block might be
        ;; larger than what the caller originally requested, so from their
        ;; perspective we're "growing" the block. This would happen if there
        ;; was some internal fragmentation in the original block.
        (if ;; $size <= sizeOf($address)
            (i32.le_s
                (local.get $size)
                (i32.load ;; sizeOf($address)
                    (i32.sub
                        (local.get $address)
                        (i32.const 4)
                    )
                )
            )
            ;; Return the block as is.
            (then (return (local.get $address)))
        )

        ;; The new size doesn't fit in the current block so we'll allocate
        ;; another block, copy the contents, and deallocate the old one.

        ;; Copy the contents of the old block to a new block.
        (memory.copy
            ;; The destination is the address of a new block that we allocate by
            ;; calling $alloc. We store the new block's address in $new.
            (local.tee $new (call $alloc (local.get $size)))
             ;; The source is the address of the original block.
            (local.get $address)
            ;; The number of bytes to copy is the size of the original block
            ;; (which is an amount of 32-bit words) times four bytes.
            (i32.mul
                (i32.load ;; sizeOf($address)
                    (i32.sub
                        (local.get $address)
                        (i32.const 4)
                    )
                )
                (i32.const 4)
            )
        )

        ;; Deallocate the old block.
        (call $dealloc (local.get $address))

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
