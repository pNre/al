#
#   [TEXT]
#
.text
.globl _main

.set obj_type.nil,      1
.set obj_type.cons,     2
.set obj_type.symbol,   3
.set obj_type.integer,  4
.set obj_type.double,   5
.set obj_type.builtin,  6
.set obj_type.lambda,   7

.set obj_field.type,    0
.set obj_field.value,   8
.set obj.size,          16

.set cons_field.car,     0
.set cons_field.cdr,     8
.set cons.size,          16

.set return.ok,                 0
.set return.syntax_error,       1
.set return.undefined_symbol,   2
.set return.wrong_arg_count,    3
.set return.type_mismatch,      4

_main:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32
    push    rbx
    push    r12

    # create the environment
    lea     rdi, [rip + obj.nil]
    call    new_env
    mov     rbx, rax
    # load builtins
    mov     rdi, rbx
    call    env_load_builtins

_main.read:
    lea     rdi, [rip + prompt]
    call    _readline
    mov     r12, rax
    cmp     rax, 0
    je      _main.read

    # save the input string into the history
    mov     rdi, r12
    call    _add_history

    # parse the input string
    mov     rdi, r12
    mov     [rbp - 8], rdi
    lea     rsi, [rbp - 8]
    lea     rdx, [rbp - 16]
    call    read_expr
    cmp     rax, return.ok
    jne     _main.error

    # free the input buffer
    mov     rdi, r12
    call    _free

    # evaluate and store the evalutation result
    # onto the stack
    mov     rdi, [rbp - 16]
    mov     rsi, rbx
    lea     rdx, [rbp - 24]
    call    eval_expr
    cmp     rax, return.ok
    jne     _main.error

    # print the evalutation result
    mov     rdi, [rbp - 24]
    call    print_expr

    xor     rax, rax
    lea     rdi, [rip + debug.newline]
    call    _printf

    # again
    jmp     _main.read

_main.error:
    lea     r12, [rip + errors]
    imul    rax, 8
    add     r12, rax
    xor     rax, rax
    mov     rdi, [r12]
    call    _printf
    jmp     _main.read

_main.fail:
    mov     rax, 1

_main.done:
    pop     r12
    pop     rbx
    add     rsp, 32
    leave
    ret

/**
    Evaluates an expression.
    rdi: expression
    rsi: env
    rdx: result
*/
eval_expr:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    
    # save args 
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    # get the expr type
    movsx   r14, byte ptr [rbx + obj_field.type]

    # symbol 
    cmp     r14, obj_type.symbol
    jne     eval_expr.check_cons
    mov     rdi, r12
    mov     rsi, rbx
    mov     rdx, r13
    call    env_get
    jmp     eval_expr.done
 
eval_expr.check_cons:
    # cons
    cmp     r14, obj_type.cons
    je      eval_expr.cons

    # other
    mov     [r13], rbx
    mov     rax, return.ok
    jmp     eval_expr.done

eval_expr.cons:
    # check that the expression is a proper list
    mov     rdi, rbx
    call    list?
    mov     rax, return.syntax_error
    jne     eval_expr.done
    # operator
    mov     rdi, rbx
    call    car
    mov     r14, rax
    # args
    mov     rdi, rbx
    call    cdr
    mov     r15, rax
    # make sure the operator is a symbol
    cmp     byte ptr [r14 + obj_field.type], obj_type.symbol 
    mov     rax, return.syntax_error
    jne     eval_expr.function
    # op: quote
    mov     rdi, [r14 + obj_field.value]
    lea     rsi, [rip + operator.quote]
    call    _strcmp
    cmp     rax, 0
    je      eval_expr.operator.quote
    # op: def
    mov     rdi, [r14 + obj_field.value]
    lea     rsi, [rip + operator.def]
    call    _strcmp
    cmp     rax, 0
    je      eval_expr.operator.def
    # op: lambda
    mov     rdi, [r14 + obj_field.value]
    lea     rsi, [rip + operator.lambda]
    call    _strcmp
    cmp     rax, 0
    je      eval_expr.operator.lambda
    # op: function
    jmp     eval_expr.function

eval_expr.operator.quote:
    # make sure the operator has 1 arg
    mov     rdi, r15
    call    list_length
    cmp     rax, 1
    mov     rax, return.wrong_arg_count    
    jne     eval_expr.done
    #
    mov     rdi, r15
    call    car
    mov     [r13], rax
    mov     rax, return.ok
    jmp     eval_expr.done

eval_expr.operator.def:
    # make sure the operator has 2 args
    mov     rdi, r15
    call    list_length
    cmp     rax, 2
    mov     rax, return.wrong_arg_count    
    jne     eval_expr.done
    #
    mov     rdi, r15
    call    car
    mov     r14, rax
    cmp     byte ptr [r14 + obj_field.type], obj_type.symbol
    mov     rax, return.type_mismatch
    jne     eval_expr.done

    mov     rdi, r15
    call    cdr
    mov     rdi, rax
    call    car
    mov     rdi, rax
    mov     rsi, r12
    lea     rdx, [rbp - 8]
    call    eval_expr
    cmp     rax, return.ok
    jne     eval_expr.done

    mov     [r13], r14
    mov     rdi, r12
    mov     rsi, r14
    mov     rdx, [rbp - 8]
    call    env_set
    jmp     eval_expr.done

eval_expr.operator.lambda:
    # make sure the operator has at least 2 args
    mov     rdi, r15
    call    list_length
    cmp     rax, 2
    mov     rax, return.wrong_arg_count
    jl      eval_expr.done 

    # lambda args
    mov     rdi, r15
    call    car
    mov     r14, rax

    # lambda body
    mov     rdi, r15
    call    cdr
    mov     r15, rax

    # make the lambda obj
    mov     rdi, r12
    mov     rsi, r14
    mov     rdx, r15
    mov     rcx, r13
    call    new_lambda
    jmp     eval_expr.done

eval_expr.function:
    mov     [rbp - 8], r14
    # evalute operator
    mov     rdi, r14
    mov     rsi, r12
    lea     rdx, [rbp - 8]
    call    eval_expr
    cmp     rax, return.ok
    jne     eval_expr.done
    mov     rdi, r15
    call    copy_list
    mov     r15, rax
    mov     rbx, rax
    mov     rdi, rax
    # evaluate args
eval_expr.function.next_arg:
    call    nil?
    je      eval_expr.function.apply
    mov     rdx, [rbx + obj_field.value]
    mov     rdi, [rdx + cons_field.car]
    mov     rsi, r12
    lea     rdx, [rdx + cons_field.car]
    call    eval_expr
    cmp     rax, return.ok
    jne     eval_expr.done
    mov     rdi, rbx
    call    cdr
    mov     rbx, rax
    mov     rdi, rax
    jmp     eval_expr.function.next_arg

eval_expr.function.apply:
    mov     rdi, [rbp - 8]
    mov     rsi, r15
    mov     rdx, r13
    call    apply

eval_expr.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    add     rsp, 8
    leave
    retn


/**
    Calls a function.
    rdi: obj 
    rsi: args
    rdx: result pointer
*/

apply:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 24
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx 

    cmp     byte ptr [rbx + obj_field.type], obj_type.builtin
    je      apply.builtin
    cmp     byte ptr [rbx + obj_field.type], obj_type.lambda
    je      apply.lambda
    mov     rax, return.type_mismatch
    jmp     apply.done

apply.lambda:
    mov     rdi, rbx
    call    car
    mov     rdi, rax
    call    new_env
    # env
    mov     r14, rax
    # arg symbols
    mov     rdi, rbx
    call    cdr
    mov     rdi, rax
    call    car
    mov     r15, rax 
    # fn body
    mov     rdi, rbx
    call    cdr
    mov     rdi, rax
    call    cdr
    mov     [rbp - 8], rax

    # bind the args
    mov     rdi, r15

apply.lambda_bind_next:
    call    nil?
    je      apply.lambda_evaluate
    # no args left
    mov     rdi, r12
    call    nil?
    mov     rax, return.wrong_arg_count
    je      apply.done
    # bind
    # symbol
    mov     rdi, r15
    call    car
    mov     [rbp - 16], rax
    # value
    mov     rdi, r12
    call    car
    mov     [rbp - 24], rax
    # set env
    mov     rdi, r14
    mov     rsi, [rbp - 16]
    mov     rdx, [rbp - 24]
    call    env_set
    # next symbol
    mov     rdi, r15
    call    cdr
    mov     r15, rax
    # next arg
    mov     rdi, r12
    call    cdr
    mov     r12, rax
    # loop
    mov     rdi, r15
    jmp     apply.lambda_bind_next

apply.lambda_evaluate:
    # check that there's no arg value left
    mov     rdi, r12
    call    nil?
    mov     rax, return.wrong_arg_count
    jne     apply.done 
    # evaluate the body of the lambda
    mov     rdi, [rbp - 8]

apply.lambda_evaluate_body_next:
    call    nil?
    mov     rax, return.ok
    je      apply.done
    # current statement
    mov     rdi, [rbp - 8]
    call    car
    # eval
    mov     rdi, rax
    mov     rsi, r14
    mov     rdx, r13
    call    eval_expr
    cmp     rax, return.ok
    jne     apply.done
    # next statement
    mov     rdi, [rbp - 8]
    call    cdr
    mov     [rbp - 8], rax
    mov     rdi, rax
    jmp     apply.lambda_evaluate_body_next

apply.builtin:
    mov     r8, [rbx + obj_field.value]
    mov     rdi, r12
    mov     rsi, r13
    call    r8

apply.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    add     rsp, 24
    leave
    ret

/**
    Copies a list.
    rdi: list
*/
copy_list:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi

    call    nil?
    je      copy_list.nil

    mov     rdi, rbx
    call    car
    mov     rdi, rax
    lea     rsi, [rip + obj.nil]
    call    cons
    mov     r12, rax
    mov     r13, rax

copy_list.next:
    mov     rdi, rbx
    call    cdr
    mov     rbx, rax
    mov     rdi, rax
    call    nil?
    je      copy_list.exit
    mov     rdi, rbx
    call    car
    mov     rdi, rax
    lea     rsi, [rip + obj.nil]
    call    cons
    mov     r12, [r12 + obj_field.value]
    mov     [r12 + cons_field.cdr], rax
    mov     r12, [r12 + cons_field.cdr]
    jmp     copy_list.next

copy_list.exit:
    mov     rax, r13
    jmp     copy_list.done

copy_list.nil:
    lea     rax, [rip + obj.nil]

copy_list.done:
    pop     r13
    pop     r12
    pop     rbx
    add     rsp, 8
    leave
    ret

/**
    Parses a list.
    rdi: start
    rsi: end
    rdx: result
*/
read_list:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 24
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    # save args
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    # end = start
    mov     [rsi], rdi
    # item_ptr = result = nil
    lea     rax, [rip + obj.nil]
    mov     [rbp - 24], rax
    mov     [r13], rax

read_list.continue:
    # get the next token
    mov     rdi, [r12]
    lea     rsi, [rbp - 8]
    mov     rdx, r12
    call    next_token
    cmp     rax, return.ok
    jne     read_list.done
    # a ) token means the list is over
    mov     r14, [rbp - 8]
    cmp     byte ptr [r14], ')'
    je      read_list.done
    #
    mov     rdi, [rbp - 8]
    mov     rsi, r12
    lea     rdx, [rbp - 16]
    call    read_expr
    cmp     rax, return.ok
    jne     read_list.done
    # 1st item?
    mov     rdi, [rbp - 24]
    call    nil?
    jne     read_list.nth_item
    #
    mov     rdi, [rbp - 16]
    lea     rsi, [rip + obj.nil]
    call    cons
    mov     [r13], rax
    mov     [rbp - 24], rax
    jmp     read_list.continue

read_list.nth_item:
    mov     rdi, [rbp - 16]
    lea     rsi, [rip + obj.nil]
    call    cons
    
    mov     r15, [rbp - 24]
    mov     r15, [r15 + obj_field.value]
    mov     [r15 + cons_field.cdr], rax
    mov     [rbp - 24], rax 
    
    jmp     read_list.continue

read_list.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    add     rsp, 24
    leave
    ret


/**
    Reads an expression.
    rdi: start
    rsi: end
    rdx: result
*/

read_expr:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    # move to the next token
    mov     rdi, rbx
    lea     rsi, [rbp - 8]
    mov     rdx, r12
    call    next_token
    cmp     rax, return.ok
    jne     read_expr.done

    # *token == '(', new list
    mov     r14, [rbp - 8] 
    cmp     byte ptr [r14], '('
    je      read_expr.list
    # *token == ')', syntax error
    cmp     byte ptr [r14], ')'
    mov     rax, return.syntax_error
    je      read_expr.done
    # the token is an expression
    mov     rdi, [rbp - 8]
    mov     rsi, [r12]
    mov     rdx, r13
    call    read_objs
    jmp     read_expr.done

read_expr.list:
    mov     rdi, [r12]
    mov     rsi, r12
    mov     rdx, r13
    call    read_list

read_expr.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    add     rsp, 16
    leave
    ret

/**
    Parses a non-list token.
    rdi: start
    rsi: end
    rdx: result
*/
read_objs:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    # try to parse the token as a base 10 int
    lea     rsi, [rbp - 8]
    mov     rdx, 10
    call    _strtol
    # make sure there isn't any non numeric character left
    cmp     [rbp - 8], r12
    jne     read_objs.test_double
    # make an int 
    mov     rdi, rax
    call    new_int
    mov     [r13], rax
    jmp     read_objs.done

read_objs.test_double:
    # try to parse the token as a double
    mov     rdi, rbx
    lea     rsi, [rbp - 8]
    call    _strtod
    # make sure there isn't any non numeric character left
    cmp     [rbp - 8], r12
    jne     read_objs.test_nil
    # make a dobule 
    call    new_double
    mov     [r13], rax
    jmp     read_objs.done

read_objs.test_nil:
    # check that the token is "nil"
    mov     rdi, rbx
    lea     rsi, [rip + parser.nil]
    call    _strcasecmp
    cmp     rax, 0
    je      read_objs.nil
    # it isn't nil, must be a new symbol
    mov     rdi, rbx
    mov     rsi, r12
    sub     rsi, rbx
    call    strncpyz
    # make a symbol
    mov     rdi, rax
    call    new_symbol
    mov     [r13], rax
    jmp     read_objs.done

read_objs.nil:
    lea     r12, [rip + obj.nil]
    mov     [r13], r12

read_objs.done:
    mov     rax, return.ok
    pop     r13
    pop     r12
    pop     rbx
    add     rsp, 8
    leave
    ret

/**
    Gets the next token in a string.
    rdi: string
    rsi: start ptr
    rdx: end ptr
*/
next_token:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    push    rbx
    push    r12
    push    r13
    # save the string pointer
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    # get the offset of the first non whitespace character in the input string
    lea     rsi, [rip + tokenizer.whitespaces]
    call    _strspn
    # move the string pointer to the offset returned by strspn
    add     rbx, rax
    # fail if the offset is out of bounds
    cmp     byte ptr [rbx], 0
    je      next_token.fail
    # set the token start address
    mov     [r12], rbx
    # the token is a ( or )
    cmp     byte ptr [rbx], '('
    je      next_token.skip_one
    cmp     byte ptr [rbx], ')'
    je      next_token.skip_one
    # the token is something else
    mov     rdi, rbx
    lea     rsi, [rip + tokenizer.delimiters]
    call    _strcspn
    add     rbx, rax
    jmp     next_token.success
next_token.skip_one:
    add     rbx, 1
    jmp     next_token.success
next_token.fail:
    mov     rax, return.syntax_error
    mov     qword ptr [r12], 0
    mov     qword ptr [r13], 0
    jmp     next_token.done
next_token.success:
    mov     rax, return.ok
    mov     [r13], rbx
next_token.done:
    pop     r13
    pop     r12
    pop     rbx
    add     rsp, 8
    leave
    ret

/**
    Creates an environment.
    rdi: parent
*/
new_env:
    push    rbp
    mov     rbp, rsp
    lea     rsi, [rip + obj.nil]
    call    cons
    leave
    ret

/**
    Sets a binding in an environment.
    rdi: env
    rsi: symbol
    rdx: value
*/
env_set:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     [rbp - 8], rdi
    mov     rbx, rsi
    mov     r12, rdx 

env_set.next:
    call    cdr
    mov     r13, rax

    mov     rdi, r13
    call    nil?
    je      env_set.not_found
    
    mov     rdi, r13
    call    car
    mov     r14, rax

    mov     rdi, rax
    call    car
    mov     r15, rax
    
    mov     rdi, [r15 + obj_field.value]
    mov     rsi, [rbx + obj_field.value] 
    call    _strcmp
    cmp     rax, 0
    je      env_set.found

    mov     rdi, r13
    jmp     env_set.next

env_set.found:
    mov     rdi, [r14 + obj_field.value]
    mov     [rdi + cons_field.cdr], r12
    mov     rax, return.ok
    jmp     env_set.done

env_set.not_found:
    mov     rdi, rbx
    mov     rsi, r12
    call    cons
    mov     r12, rax
    mov     rdi, [rbp - 8]
    call    cdr
    mov     rdi, r12
    mov     rsi, rax
    call    cons
    mov     rdi, [rbp - 8]
    mov     rdi, [rdi + obj_field.value]
    mov     [rdi + cons_field.cdr], rax
    mov     rax, return.ok

env_set.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    add     rsp, 8
    leave
    ret

/**
    Retrieves a binding in an environment.
    rdi: env
    rsi: symbol
    rdx: result
*/
env_get:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
   
    mov     [rbp - 8], rdi
    mov     rbx, rsi
    mov     r12, rdx 

env_get.next:
    call    cdr
    mov     r13, rax

    mov     rdi, r13
    call    nil?
    je      env_get.parent
    
    mov     rdi, r13
    call    car
    mov     r14, rax

    mov     rdi, rax
    call    car
    mov     r15, rax
    
    mov     rdi, [r15 + obj_field.value]
    mov     rsi, [rbx + obj_field.value] 
    call    _strcmp
    cmp     rax, 0
    je      env_get.found

    mov     rdi, r13
    jmp     env_get.next

env_get.found:
    mov     rdi, r14
    call    cdr
    mov     [r12], rax
    mov     rax, return.ok
    jmp     env_get.done
    
env_get.parent:
    mov     rdi, [rbp - 8]
    call    car
    mov     r14, rax
    mov     rdi, r14
    call    nil?
    mov     rax, return.undefined_symbol
    je      env_get.done
    mov     rdi, r14
    mov     rsi, rbx
    mov     rdx, r12
    call    env_get

env_get.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    add     rsp, 8
    leave
    ret

/**
    Creates a lambda obj.
    rdi: env
    rsi: args
    rdx: body
    rcx: pointer to the address of the resulting object
*/
new_lambda:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14

    # save args
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    
    # both rsi and rdx must point to a list
    mov     rdi, r12
    call    list?
    mov     rax, return.syntax_error
    jne     new_lambda.done

    mov     rdi, r13
    call    list?
    mov     rax, return.syntax_error
    jne     new_lambda.done

    # each arg must be a symbol
    mov     rdi, r12
    lea     rdx, [rip + check_obj_symbol]
    call    list_fold
    cmp     rax, return.ok
    jne     new_lambda.done

    # make the obj
    mov     rdi, r12
    mov     rsi, r13
    call    cons
    mov     rdi, rbx
    mov     rsi, rax
    call    cons
    mov     byte ptr [rax + obj_field.type], obj_type.lambda
    mov     [r14], rax
    mov     rax, return.ok

new_lambda.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    leave
    ret 

/**
*/
check_obj_symbol:
    push    rbp
    mov     rbp, rsp
    cmp     byte ptr [rdi + obj_field.type], obj_type.symbol
    je      check_obj_symbol.ok
    mov     rax, return.type_mismatch
    jmp     check_obj_symbol.done
 
check_obj_symbol.ok:
    mov     rax, return.ok

check_obj_symbol.done: 
    leave
    ret

/**
    Creates a symbol obj.
    rdi: symbol
*/
new_symbol:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rdi
    # alloc space for a new obj
    mov     rdi, obj.size
    call    _malloc
    mov     r12, rax
    # set type to "symbol"
    mov     byte ptr [r12], obj_type.symbol
    # copy the symbol
    mov     rdi, rbx
    call    _strdup
    # set value to rax
    mov     qword ptr [r12 + obj_field.value], rax
    mov     rax, r12
    pop     r12
    pop     rbx
    leave
    ret

/**
    Creates a double obj.
    xmm0: value
*/
new_double:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    # preserve the value
    movsd   qword ptr [rbp - 8], xmm0
    # alloc space for a new obj
    mov     rdi, obj.size
    call    _malloc
    # set type
    mov     byte ptr [rax], obj_type.double
    # set value
    movsd   xmm0, qword ptr [rbp - 8]
    movsd   qword ptr [rax + obj_field.value], xmm0
    add     rsp, 16
    leave
    ret

/**
    Creates an integer obj.
    rdi: value
*/
new_int:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    push    rdi
    # alloc space for a new obj
    mov     rdi, obj.size
    call    _malloc
    # set type to "integer"
    mov     byte ptr [rax], obj_type.integer
    # set value to rdi
    pop     rdi
    mov     qword ptr [rax + obj_field.value], rdi
    add     rsp, 8
    leave
    ret

/**
    Creates an builtin obj.
    rdi: function pointer
*/
new_builtin:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    push    rdi
    # alloc space for a new obj
    mov     rdi, obj.size
    call    _malloc
    # set type to "builtin"
    mov     byte ptr [rax], obj_type.builtin
    # set value to rdi
    pop     rdi
    mov     qword ptr [rax + obj_field.value], rdi
    add     rsp, 8
    leave
    ret

/**
    Makes a cons.
    rdi: left
    rsi: right
*/
cons:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    push    rbx
    # save the args for later
    push    rdi
    push    rsi
    # alloc space for a new obj
    mov     rdi, obj.size
    call    _malloc
    # save the address
    mov     rbx, rax
    # set type to "cons"
    mov     byte ptr [rbx], obj_type.cons
    # alloc space for the cons elements pointers
    mov     rdi, cons.size
    call    _malloc
    # set the value to the allocated buffer
    mov     qword ptr [rbx + obj_field.value], rax
    # set cdr
    pop     rsi
    mov     qword ptr [rax + cons_field.cdr], rsi
    # set car
    pop     rdi
    mov     qword ptr [rax + cons_field.car], rdi
    # return the obj
    mov     rax, rbx
    pop     rbx
    add     rsp, 8
    leave
    ret

/**
    Returns the left element of in a cons.
    rdi: cons
*/
car:
    push    rbp
    mov     rbp, rsp
    mov     rsi, [rdi + obj_field.value]
    mov     rax, [rsi + cons_field.car]
    leave
    ret

/**
    Returns the right element of in a cons.
    rdi: cons
*/
cdr:
    push    rbp
    mov     rbp, rsp
    mov     rsi, [rdi + obj_field.value]
    mov     rax, [rsi + cons_field.cdr]
    leave
    ret

/**
    Checks whether an obj is nil.
*/
nil?:
    push    rbp
    mov     rbp, rsp
    movsx   rsi, byte ptr [rdi + obj_field.type]
    cmp     rsi, obj_type.nil
    leave
    ret

/**
    Checks whether an expression is a list
    rdi: expression
*/
list?:
    push    rbp
    mov     rbp, rsp
    push    rbx
    mov     rbx, rdi
    
list?.continue:
    mov     rdi, rbx
    call    nil?
    je      list?.done 
    cmp     byte ptr [rbx + obj_field.type], obj_type.cons
    jne     list?.done
    mov     rdi, rbx
    call    cdr
    mov     rbx, rax
    jmp     list?.continue

list?.done:
    pop     rbx
    leave
    ret

/**
    Prints an obj.
*/
print_expr:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    # save the obj address in r12
    mov     r12, rdi
    # type
    movsx   rbx, byte ptr [rdi + obj_field.type]
    # clear rax (to prepare for printf)
    xor     rax, rax
    # nil
    cmp     rbx, obj_type.nil
    je      print_expr.nil
    # cons
    cmp     rbx, obj_type.cons
    je      print_expr.cons
    # symbol
    cmp     rbx, obj_type.symbol
    je      print_expr.symbol
    # integer
    cmp     rbx, obj_type.integer
    je      print_expr.integer
    # double
    cmp     rbx, obj_type.double
    je      print_expr.double
    # builtin
    cmp     rbx, obj_type.builtin
    je      print_expr.builtin
    # lambda
    cmp     rbx, obj_type.lambda
    je      print_expr.lambda
    # unknown
    jmp     print_expr.done

print_expr.nil:
    lea     rdi, [rip + obj.nil.fmt]
    call    _printf
    jmp     print_expr.done

print_expr.cons:
    # (
    lea     rdi, [rip + debug.lparen]
    call    _printf

    # print_expr(car(obj))
    mov     rdi, r12
    call    car
    mov     rdi, rax
    call    print_expr

    # obj = cdr(obj)
    mov     rdi, r12
    call    cdr
    mov     r12, rax

print_expr.cons.next:
    # check if the current obj is nil
    mov     rdi, r12
    call    nil?
    # and end if it is
    je      print_expr.cons.done

    # a cons, flatten the debug representation
    cmp     byte ptr [r12 + obj_field.type], obj_type.cons
    je      print_expr.cons.continue

    # otherwise print it and exit
    lea     rdi, [rip + debug.cons_separator]
    call    _printf
    mov     rdi, r12
    call    print_expr
    jmp     print_expr.cons.done

print_expr.cons.continue:
    lea     rdi, [rip + debug.list_separator]
    call    _printf
    mov     rdi, r12
    call    car
    mov     rdi, rax
    call    print_expr
    mov     rdi, r12
    call    cdr
    mov     r12, rax
    jmp     print_expr.cons.next

print_expr.cons.done:
    lea     rdi, [rip + debug.rparen]
    call    _printf
    jmp     print_expr.done

print_expr.symbol:
    lea     rdi, [rip + obj.symbol.fmt]
    mov     rsi, [r12 + obj_field.value]
    call    _printf
    jmp     print_expr.done

print_expr.integer:
    lea     rdi, [rip + obj.integer.fmt]
    mov     rsi, [r12 + obj_field.value]
    call    _printf
    jmp     print_expr.done

print_expr.double:
    lea     rdi, [rip + obj.double.fmt]
    movsd   xmm0, qword ptr [r12 + obj_field.value]
    mov     rax, 1
    call    _printf
    jmp     print_expr.done

print_expr.builtin:
    lea     rdi, [rip + obj.builtin.fmt]
    mov     rsi, [r12 + obj_field.value]
    call    _printf
    jmp     print_expr.done

print_expr.lambda:
    lea     rdi, [rip + obj.lambda.fmt]
    call    _printf

print_expr.done:
    pop     r12
    pop     rbx
    leave
    ret

/**
    Copies the first rsi characters from rdi into a new buffer.
    rdi: source
    rsi: length
*/
strncpyz:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    # reserve space for the string
    mov     rdi, r12
    add     rdi, 1
    call    _malloc
    mov     r13, rax
    # copy
    mov     rdi, r13
    mov     rsi, rbx
    mov     rdx, r12
    call    _strncpy
    # set the last byte to \0
    add     r13, r12
    add     r13, 1
    mov     byte ptr [r13], 0
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    leave
    ret

/**
    Loads builtins into an environment.
    rdi: env
*/
env_load_builtins:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    mov     rbx, rdi
    lea     r12, [rip + builtins]

env_load_builtins.next:
    cmp     qword ptr [r12], 0
    je      env_load_builtins.done
    mov     rdi, rbx
    mov     rsi, [r12]
    mov     rdx, [r12 + 8]
    call    env_set_builtin
    add     r12, 8
    jmp     env_load_builtins.next

env_load_builtins.done:
    pop     r12
    pop     rbx
    leave
    ret

/**
    Adds a builtin to an environment.
    rdi: env
    rsi: symbol
    rdx: function pointer
*/
env_set_builtin:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi 
    mov     r12, rdx
    
    mov     rdi, rsi
    call    new_symbol
    mov     r13, rax
    
    mov     rdi, r12
    call    new_builtin

    mov     rdi, rbx
    mov     rsi, r13
    mov     rdx, rax
    call    env_set

    pop     r13
    pop     r12
    pop     rbx
    add     rsp, 8
    leave
    ret

/**
    Returns the length of a list.
*/
list_length:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12

    mov     rbx, rdi
    mov     r12, 0

list_length.next:
    call    nil?
    je      list_length.done
    mov     rdi, rbx
    call    cdr
    mov     rbx, rax
    mov     rdi, rax
    add     r12, 1
    jmp     list_length.next

list_length.done:
    mov     rax, r12
    pop     r12
    pop     rbx
    leave
    ret

/**
    Folds a list.
    rdi: list
    rsi: accumulator address
    rdx: function
*/
list_fold:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 8
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    jmp     list_fold.first

list_fold.next:
    call    nil?
    je      list_fold.ok

list_fold.first:
    mov     rdi, rbx
    call    car
    mov     rdi, rax
    mov     rsi, r12
    call    r13
    cmp     rax, return.ok
    jne     list_fold.done
    mov     rdi, rbx
    call    cdr
    mov     rbx, rax
    mov     rdi, rax
    jmp     list_fold.next

list_fold.ok:
    mov     rax, return.ok
list_fold.done:
    pop     r13
    pop     r12
    pop     rbx
    add     rsp, 8
    leave
    ret


/**
*/
check_obj_numeric:
    push    rbp
    mov     rbp, rsp
    cmp     byte ptr [rdi + obj_field.type], obj_type.integer
    je      check_obj_numeric.ok
    cmp     byte ptr [rdi + obj_field.type], obj_type.double
    je      check_obj_numeric.ok
    mov     rax, return.type_mismatch
    jmp     check_obj_numeric.done
 
check_obj_numeric.ok:
    mov     rax, return.ok

check_obj_numeric.done: 
    leave
    ret

/**
    CAR
*/
builtin.car:
    push    rbp
    mov     rbp, rsp
    mov     rdx, rsi
    mov     rsi, rdi
    lea     rdi, [rip + car]
    call    builtin.cons_term
    leave
    ret

/**
    CDR
*/
builtin.cdr:
    push    rbp
    mov     rbp, rsp
    mov     rdx, rsi
    mov     rsi, rdi
    lea     rdi, [rip + cdr]
    call    builtin.cons_term
    leave
    ret

/**
    CAR/CDR
    rdi: car/cdr function pointer
    rsi: args
    rdx: result
*/
builtin.cons_term:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    mov     rdi, r12
    call    nil?
    mov     rax, return.wrong_arg_count
    je      builtin.cons_term.done
    mov     rdi, r12
    call    cdr
    mov     rdi, rax
    call    nil?
    mov     rax, return.wrong_arg_count
    jne     builtin.cons_term.done

    mov     rdi, r12
    call    car
    mov     r14, rax
    mov     rdi, rax
    call    nil?
    je      builtin.cons_term.nil

    cmp     byte ptr [r14 + obj_field.type], obj_type.cons
    mov     rax, return.type_mismatch
    jne     builtin.cons_term.done

    mov     rdi, r14
    call    rbx
    mov     [r13], rax
    mov     rax, return.ok
    jmp     builtin.cons_term.done 
    
builtin.cons_term.nil:
    lea     rax, [rip + obj.nil]
    mov     [r13], rax
    mov     rax, return.ok

builtin.cons_term.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    leave
    ret

/**
    CAR/CDR
    rdi: args
    rsi: result
*/
builtin.cons:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi
    mov     r12, rsi

    call    nil?
    mov     rax, return.wrong_arg_count
    je      builtin.cons.done
    mov     rdi, rbx
    call    cdr
    mov     r13, rax
    mov     rdi, rax
    call    nil?
    mov     rax, return.wrong_arg_count
    je      builtin.cons.done
    mov     rdi, r13
    call    cdr
    mov     rdi, rax
    call    nil?
    mov     rax, return.wrong_arg_count
    jne     builtin.cons.done

    mov     rdi, rbx
    call    car
    mov     r14, rax

    mov     rdi, r13
    call    car
    
    mov     rdi, r14
    mov     rsi, rax
    call    cons

    mov     [r12], rax
    mov     rax, return.ok

builtin.cons.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    leave
    ret

/**
    Arithmetic operation.
    rdi: operation function pointer
    rsi: args
    rdx: result
*/
builtin.arit:
    push        rbp
    mov         rbp, rsp
    sub         rsp, 24
    push        rbx
    push        r12
    push        r13
    push        r14
    push        r15

    mov         rbx, rdi
    mov         r12, rsi
    mov         r13, rdx

    # arithmetic ops require 2 args 
    mov         rdi, r12
    call        list_length
    cmp         rax, 2
    mov         rax, return.wrong_arg_count
    jne         builtin.arit.done

    # load the first 2 args
    # (car args)
    # (car (cdr args))
    mov         rdi, r12
    call        car
    mov         r14, rax
    mov         rdi, r12
    call        cdr
    mov         rdi, rax
    call        car
    mov         r15, rax

    # check that the args type is either integer or double
    mov         rdi, r12
    lea         rdx, [rip + check_obj_numeric]
    call        list_fold
    cmp         rax, return.ok
    jne         builtin.arit.done 

    # [rbp - 8] holds the number of fp arguments
    mov         qword ptr [rbp - 8], 0 
 
    # check that the args type is integer
    cmp         byte ptr [r14 + obj_field.type], obj_type.integer
    jne         1f
    cmp         byte ptr [r15 + obj_field.type], obj_type.integer
    jne         1f
    
    # load values
    mov         rax, [rbp - 8]
    mov         rdi, [r14 + obj_field.value]
    mov         rsi, [r15 + obj_field.value]
    # result
    lea         rdx, [rbp - 16]

    # call the op
    call        rbx

    # return 
    mov         rdi, [rbp - 16]
    call        new_int
    jmp         builtin.arit.result
 
1:
    # set the fp counter
    mov         qword ptr [rbp - 8], 2
    # read the obj value as double
    movsd       xmm0, [r14 + obj_field.value]
    # in case the arg is actually a double, check the other one
    cmp         byte ptr [r14 + obj_field.type], obj_type.double
    je          2f
    # not a double, convert the int value to double
    mov         r14, [r14 + obj_field.value]
    cvtsi2sd    xmm0, r14

2:
    # read the obj value as double
    movsd       xmm1, [r15 + obj_field.value]
    # in case the arg is actually a double, call the op
    cmp         byte ptr [r15 + obj_field.type], obj_type.double
    je          builtin.arit.call_fp
    # not a double, convert the int value to double
    mov         r15, [r15 + obj_field.value]
    cvtsi2sd    xmm1, r15

builtin.arit.call_fp:
    # load values
    mov         rax, [rbp - 8]
    # result
    lea         rdx, [rbp - 16]
    # call the op
    call        rbx
    # new dobule
    movsd       xmm0, [rbp - 16]
    call        new_double
    jmp         builtin.arit.result

builtin.arit.result:
    mov         [r13], rax
    mov         rax, return.ok

builtin.arit.done:
    pop         r15
    pop         r14
    pop         r13
    pop         r12
    pop         rbx
    add         rsp, 24
    leave
    ret

/**
    +
*/
builtin.add:
    push    rbp
    mov     rbp, rsp
    mov     rdx, rsi
    mov     rsi, rdi
    lea     rdi, [rip + builtin.add_op]
    call    builtin.arit
    leave
    ret

builtin.add_op:
    push    rbp
    mov     rbp, rsp
    test    rax, rax
    jnz     builtin.add_op.fp
    add     rdi, rsi
    mov     [rdx], rdi
    jmp     builtin.add_op.done

builtin.add_op.fp:
    addsd   xmm0, xmm1
    movsd   [rdx], xmm0

builtin.add_op.done:
    leave
    ret

/**
    -
*/
builtin.sub:
    push    rbp
    mov     rbp, rsp
    mov     rdx, rsi
    mov     rsi, rdi
    lea     rdi, [rip + builtin.sub_op]
    call    builtin.arit
    leave
    ret

builtin.sub_op:
    push    rbp
    mov     rbp, rsp
    test    rax, rax
    jnz     builtin.sub_op.fp
    sub     rdi, rsi
    mov     [rdx], rdi
    jmp     builtin.sub_op.done

builtin.sub_op.fp:
    subsd   xmm0, xmm1
    movsd   [rdx], xmm0

builtin.sub_op.done:
    leave
    ret

/**
    *
*/
builtin.mul:
    push    rbp
    mov     rbp, rsp
    mov     rdx, rsi
    mov     rsi, rdi
    lea     rdi, [rip + builtin.mul_op]
    call    builtin.arit
    leave
    ret

builtin.mul_op:
    push    rbp
    mov     rbp, rsp
    test    rax, rax
    jnz     builtin.mul_op.fp
    imul    rdi, rsi
    mov     [rdx], rdi
    jmp     builtin.mul_op.done

builtin.mul_op.fp:
    mulsd   xmm0, xmm1
    movsd   [rdx], xmm0

builtin.mul_op.done:
    leave
    ret

/**
    /
*/
builtin.div:
    push    rbp
    mov     rbp, rsp
    mov     rdx, rsi
    mov     rsi, rdi
    lea     rdi, [rip + builtin.div_op]
    call    builtin.arit
    leave
    ret

builtin.div_op:
    push    rbp
    mov     rbp, rsp
    test    rax, rax
    jnz     builtin.div_op.fp
    mov     r8, rdx
    xor     rdx, rdx
    mov     rax, rdi
    idiv    rsi
    mov     [r8], rax
    jmp     builtin.div_op.done

builtin.div_op.fp:
    divsd   xmm0, xmm1
    movsd   [rdx], xmm0

builtin.div_op.done:
    leave
    ret

#
#   [DATA]
#
.data

obj.nil:
    .byte obj_type.nil
    .fill 7
    .quad 0

obj.nil.fmt:
    .string "nil"
obj.symbol.fmt:
    .string "%s"
obj.integer.fmt:
    .string "%ld"
obj.double.fmt:
    .string "%f"
obj.builtin.fmt:
    .string "ƒ@%p"
obj.lambda.fmt:
    .string "λ"

operator.quote:
    .string "quote"
operator.def:
    .string "def"
operator.lambda:
    .string "lambda"

debug.cons_separator:
    .string " . "
debug.list_separator:
    .string " "
debug.lparen:
    .string "("
debug.rparen:
    .string ")"
debug.newline:
    .string "\n"

tokenizer.whitespaces:
    .string " \n"
tokenizer.delimiters:
    .string "() \n"

parser.nil:
    .string "nil"

prompt:
    .string "> "

errors:
    .quad 0
    .quad error.syntax
    .quad error.undefined
    .quad error.args
    .quad error.type

error.syntax:
    .string "Syntax error\n"
error.undefined:
    .string "Undefined symbol\n"
error.args:
    .string "Wrong args count\n"
error.type:
    .string "Type mismatch\n"

builtins:
    .quad builtin.car.symbol
    .quad builtin.car
    .quad builtin.cdr.symbol
    .quad builtin.cdr
    .quad builtin.cons.symbol
    .quad builtin.cons
    .quad builtin.add.symbol
    .quad builtin.add
    .quad builtin.sub.symbol
    .quad builtin.sub
    .quad builtin.mul.symbol
    .quad builtin.mul
    .quad builtin.div.symbol
    .quad builtin.div
    .quad 0
    .quad 0

builtin.car.symbol:
    .string "car"
builtin.cdr.symbol:
    .string "cdr"
builtin.cons.symbol:
    .string "cons"
builtin.add.symbol:
    .string "+"
builtin.sub.symbol:
    .string "-"
builtin.mul.symbol:
    .string "*"
builtin.div.symbol:
    .string "/"

/* vim: ft=gas :
*/
