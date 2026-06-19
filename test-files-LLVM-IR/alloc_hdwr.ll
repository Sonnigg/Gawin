; External declarations from your grtmem.h/c

declare i8* @hdwr_malloc(i64)
declare void @hdwr_free(i8*)

define i32 @grt_main() {
entry:
    br label %loop_header

loop_header:
    ; Loop counter %i starts at 0
    %i = phi i32 [ 0, %entry ], [ %i_next, %loop_body ]

    ; Check if we have reached 10000 iterations
    %done = icmp eq i32 %i, 100000
    br i1 %done, label %exit, label %loop_body

loop_body:
    ; Perform the 16MB allocation (16777216 bytes)
    %ptr = call i8* @hdwr_malloc(i64 16777216)
    call void @hdwr_free(i8* %ptr, i64 0) ; can be 0 due to being on Windows, otherwise would have to be 16777216

    ; Increment counter and jump back
    %i_next = add i32 %i, 1
    br label %loop_header

exit:
    ret i32 0
}