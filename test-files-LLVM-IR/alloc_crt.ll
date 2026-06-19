; External declarations from standard C runtime (libc)

declare i8* @malloc(i64)
declare void @free(i8*)

define i32 @main() {

entry:
    br label %loop_header

loop_header:
    ; Loop counter %i starts at 0
    %i = phi i32 [ 0, %entry ], [ %i_next, %loop_body ]

    ; Check if we have reached 100000 iterations
    %done = icmp eq i32 %i, 100000
    br i1 %done, label %exit, label %loop_body

loop_body:
    ; Allocate 16MB using standard malloc
    %ptr = call i8* @malloc(i64 16777216)

    ; Free immediately using standard free
    call void @free(i8* %ptr)

    ; Increment counter and loop
    %i_next = add i32 %i, 1
    br label %loop_header

exit:

    ret i32 0
}