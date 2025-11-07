
.data

 
    EPSILON: .float 1.0e-8  
    ZERO_S: .float 0.0     
    
  

    solution_vector: .space 60
	autocorr: .float 1.5625, 0.875, 0.625
	crosscorr: .float 1.075, 0.5625, 0.4

    n: .word 3

    str_prefix: .asciiz "x["
    str_suffix: .asciiz "] = "
    newline: .asciiz "\n"

.text
.globl main


main:
    # Load arg for funct call 
    la $a0, autocorr     # a0 = a (address of autocorr array a)
    la $a1, crosscorr        # a1 = b (address of crosscorr b)
    la $a2, solution_vector # a2 = solution (address of solution array)
    lw $a3, n               # a3 = n (size)
    
    move $s0, $a3           # $s0 = n 
    
    # Procedure call 
    jal solve_linear
    # reload caller data: $a2 is caller-saved and may be clobbered by the callee
    la $a2, solution_vector
    
    # Print result 
    li $t0, 0               # i = 0 
    
    move $t1, $s0           # t1 = N (n)

print_loop:
    # out-of-loop condition (if i == N)
    beq $t0, $t1, end_print_loop

    li $v0, 4
    la $a0, str_prefix
    syscall

    # 2. print 'i'
    li $v0, 1               # syscall 1 = print_integer
    move $a0, $t0           # $a0 = i
    syscall

    # 3. print "] = "
    li $v0, 4
    la $a0, str_suffix
    syscall

    # 4. calculate &solution[i]
    sll $t2, $t0, 2         # offset = i * 4
    add $t3, $a2, $t2       # address = base_address ($a2) + offset ($t2)

    # 5. Load solution[i] -> $f12 and print 
    l.s $f12, 0($t3)        # Load float from the (base + offset)
    li $v0, 2               # syscall 2 = print_float
    syscall

    li $v0, 4
    la $a0, newline
    syscall

    addi $t0, $t0, 1        # i++
    j print_loop

end_print_loop:
    li $v0, 10
    syscall

# -----------------------------------------------------------------
# void solve_linear(float* autocorr, float* crosscorr, float* solution, int n)
# -----------------------------------------------------------------
solve_linear:
    # --- Function Prologue ---
    addiu $sp, $sp, -52     # Allocate 52-byte stack frame (space for saved regs and locals)
    sw $ra, 48($sp)         # Save return address
    sw $fp, 44($sp)         # Save old frame pointer
    addiu $fp, $sp, 48      # Set up new frame pointer

    # Save $s registers
    sw $s0, 36($sp)
    sw $s1, 32($sp)
    sw $s2, 28($sp)
    sw $s3, 24($sp)
    sw $s4, 20($sp)
    sw $s5, 16($sp)         # Save $s5 (will be used for b_copy)

    # Copy arguments into $s registers
    move $s0, $a0           # $s0 = a (float* a)
    move $s1, $a1           # $s1 = b (float* b)
    move $s2, $a2           # $s2 = solution (float* solution)
    move $s3, $a3           # $s3 = n

    # float *A = malloc(n * n * sizeof(float));
    mul $a0, $s3, $s3       # $a0 = n * n
    sll $a0, $a0, 2         # $a0 = (n * n) * 4
    li $v0, 9
    syscall
    move $s4, $v0           # $s4 = A (continuous float *A pointer)

    # float *b_copy = malloc(n * sizeof(float));
    sll $a0, $s3, 2         # $a0 = n * 4
    li $v0, 9
    syscall
    move $s5, $v0           # $s5 = b_copy

    # for (int i = 0; i < n; i++) {
    li $t0, 0               # t0 = i
    sw $t0, 4($sp)          # save i
    
loop_i_copy:
    lw $t0, 4($sp)          # load i
    bge $t0, $s3, end_loop_i_copy # if i >= n, break

    # b_copy[i] = b[i];
    sll $t1, $t0, 2         # t1 = i * 4 (offset)
    add $t2, $s1, $t1       # t2 = addr(b[i])
    add $t3, $s5, $t1       # t3 = addr(b_copy[i])
    l.s $f0, 0($t2)         # $f0 = b[i]
    s.s $f0, 0($t3)         # b_copy[i] = $f0

    # for (int j = 0; j < n; j++) {
    li $t2, 0               # t2 = j
    sw $t2, 8($sp)          # save j
    
loop_j_copy:
    lw $t2, 8($sp)          # load j
    bge $t2, $s3, end_loop_j_copy # if j >= n, break

    # Get the value of a[i-j] (from float* a)
    sub $t3, $t0, $t2         # t3 = i - j
    bgez $t3, skip_abs
    sub $t3, $0, $t3
skip_abs:
	sll $t3, $t3, 2		   # t3 = |i-j|*4
    add $t3, $s0, $t3       # t3 = addr(a[|i-j|])
    l.s $f0, 0($t3)         # $f0 = a[|i-j|]

    # Calculate the address for A[i * n + j] (for float *A)
    mul $t6, $t0, $s3       # t6 = i * n
    add $t6, $t6, $t2       # t6 = i * n + j
    sll $t6, $t6, 2         # t6 = (i * n + j) * 4 (offset)
    add $t6, $s4, $t6       # t6 = addr(A[i*n+j])

    # A[i * n + j] = a[|i-j|]
    s.s $f0, 0($t6)

    addiu $t2, $t2, 1       # j++
    sw $t2, 8($sp)
    j loop_j_copy
end_loop_j_copy:

    addiu $t0, $t0, 1       # i++
    sw $t0, 4($sp)
    j loop_i_copy
end_loop_i_copy:

    # ---------------------------------------------------
    #  Gauss elimination with partial pivoting
    # ---------------------------------------------------

    # for (int k = 0; k < n; k++)
    li $t0, 0               # t0 = k
    sw $t0, 0($sp)          # Store k
    
loop_k_elim:
    lw $t0, 0($sp)          # Load k
    bge $t0, $s3, end_loop_k_elim # if k >= n, break

    # --- Pivot selection ---
    # int piv = k;
    sw $t0, 12($sp)         # piv = k

    # float maxv = fabs(A[k * n + k]);
    mul $t1, $t0, $s3       # t1 = k * n
    add $t1, $t1, $t0       # t1 = k * n + k
    sll $t1, $t1, 2         # t1 = (k*n + k) * 4
    add $t3, $s4, $t1       # t3 = addr(A[k*n + k])
    l.s $f0, 0($t3)         # $f0 = A[k*n + k]
    abs.s $f2, $f0          # $f2 = maxv = fabs(A[k*n + k])

    # for (int i = k + 1; i < n; i++)
    addiu $t4, $t0, 1       # t4 = i = k + 1
    sw $t4, 4($sp)          # Store i
    
loop_i_pivot:
    lw $t4, 4($sp)          # Load i
    bge $t4, $s3, end_loop_i_pivot # if i >= n, break

    # Get fabs(A[i * n + k])
    mul $t1, $t4, $s3       # t1 = i * n
    add $t1, $t1, $t0       # t1 = i * n + k
    sll $t1, $t1, 2         # t1 = (i*n + k) * 4
    add $t3, $s4, $t1       # t3 = addr(A[i*n + k])
    l.s $f0, 0($t3)         # $f0 = A[i*n + k]
    abs.s $f4, $f0          # $f4 = fabs(A[i*n + k])

    # if (fabs(A[i*n + k]) > maxv)
    c.le.s $f4, $f2         # if (fabs <= maxv)
    bc1t end_if_pivot       # branch if true (do nothing)

    # maxv = fabs(A[i*n + k]);
    mov.s $f2, $f4
    # piv = i;
    sw $t4, 12($sp)

end_if_pivot:
    addiu $t4, $t4, 1       # i++
    sw $t4, 4($sp)
    j loop_i_pivot
end_loop_i_pivot:

    # if (maxv < EPSILON) A[k*n + k] += EPSILON;
    l.s $f4, EPSILON
    c.lt.s $f2, $f4         # if (maxv < EPSILON)
    bc1f end_if_epsilon     # branch if false (>=)
    
    # A[k*n + k] += EPSILON
    mul $t1, $t0, $s3       # t1 = k * n
    add $t1, $t1, $t0       # t1 = k * n + k
    sll $t1, $t1, 2         # t1 = (k*n + k) * 4
    add $t3, $s4, $t1       # t3 = addr(A[k*n + k])
    l.s $f0, 0($t3)         # Load A[k*n + k]
    add.s $f0, $f0, $f4     # $f0 = A[k*n + k] + EPSILON
    s.s $f0, 0($t3)         # Store A[k*n + k]
    
end_if_epsilon:

    # --- Swap rows if needed ---
    lw $t5, 12($sp)         # t5 = piv
    lw $t0, 0($sp)          # t0 = k
    beq $t5, $t0, end_if_swap # if (piv == k), skip

    # for (int j = 0; j < n; j++)
    li $t6, 0               # t6 = j
loop_j_swap:
    bge $t6, $s3, end_loop_j_swap # if j >= n, break

    # addr_k = &A[k * n + j]
    mul $t1, $t0, $s3       # k * n
    add $t1, $t1, $t6       # k * n + j
    sll $t1, $t1, 2
    add $t1, $s4, $t1
    
    # addr_piv = &A[piv * n + j]
    mul $t7, $t5, $s3       # piv * n
    add $t7, $t7, $t6       # piv * n + j
    sll $t7, $t7, 2
    add $t7, $s4, $t7

    # Swap A[k*n+j] and A[piv*n+j]
    l.s $f0, 0($t1)         # f0 = tmp = A[k*n+j]
    l.s $f2, 0($t7)         # f2 = A[piv*n+j]
    s.s $f2, 0($t1)         # A[k*n+j] = f2
    s.s $f0, 0($t7)         # A[piv*n+j] = f0

    addiu $t6, $t6, 1       # j++
    j loop_j_swap
end_loop_j_swap:

    # Swap b_copy[k] and b_copy[piv]
    # (Use $s5 = b_copy, instead of $s1 = b)
    sll $t1, $t0, 2         # t1 = k * 4 
    add $t1, $s5, $t1       # t1 = addr(b_copy[k])
    
    sll $t7, $t5, 2         # t7 = piv * 4 
    add $t7, $s5, $t7       # t7 = addr(b_copy[piv])
    
    l.s $f0, 0($t1)         # $f0 = tb = b_copy[k]
    l.s $f2, 0($t7)         # $f2 = b_copy[piv]
    s.s $f2, 0($t1)         # b_copy[k] = b_copy[piv]
    s.s $f0, 0($t7)         # b_copy[piv] = tb

end_if_swap:

    # --- Elimination ---
    # Load A[k*n + k]
    mul $t1, $t0, $s3       # k * n
    add $t1, $t1, $t0       # k * n + k
    sll $t1, $t1, 2
    add $t3, $s4, $t1
    l.s $f10, 0($t3)        # $f10 = A[k*n + k]
    
    abs.s $f12, $f10
    l.s $f14, EPSILON
    l.s $f16, ZERO_S        # $f16 = 0.0

    # for (int i = k + 1; i < n; i++)
    addiu $t4, $t0, 1       # t4 = i = k + 1
    sw $t4, 4($sp)
    
loop_i_elim:
    lw $t4, 4($sp)          # Load i
    bge $t4, $s3, end_loop_i_elim # if i >= n, break

    # factor = (fabs(A[k*n+k]) < EPSILON) ? 0.0 : (A[i*n+k] / A[k*n+k]);
    c.lt.s $f12, $f14       # if (fabs(A[k*n+k]) < EPSILON)
    bc1f elim_factor_calc   # branch if false
    
    mov.s $f18, $f16        # $f18 = factor = 0.0
    j elim_factor_done
    
elim_factor_calc:
    # Lấy A[i*n + k]
    mul $t1, $t4, $s3       # i * n
    add $t1, $t1, $t0       # i * n + k
    sll $t1, $t1, 2
    add $t3, $s4, $t1
    l.s $f20, 0($t3)        # $f20 = A[i*n + k]
    div.s $f18, $f20, $f10  # $f18 = factor = A[i*n+k] / A[k*n+k]
    
elim_factor_done:

    # b_copy[i] -= factor * b_copy[k];
    # (Dùng $s5 = b_copy)
    sll $t1, $t4, 2         # i * 4
    add $t1, $s5, $t1       # addr(b_copy[i])
    l.s $f20, 0($t1)        # $f20 = b_copy[i]
    
    sll $t2, $t0, 2         # k * 4
    add $t2, $s5, $t2       # addr(b_copy[k])
    l.s $f22, 0($t2)        # $f22 = b_copy[k]
    
    mul.s $f24, $f18, $f22  # $f24 = factor * b_copy[k]
    sub.s $f20, $f20, $f24  # $f20 = b_copy[i] - ...
    s.s $f20, 0($t1)        # Store b_copy[i]

    # for (int j = k; j < n; j++)
    move $t5, $t0           # t5 = j = k
    sw $t5, 8($sp)
    
loop_j_elim:
    lw $t5, 8($sp)          # Load j
    bge $t5, $s3, end_loop_j_elim # if j >= n, break
    
    # A[i*n + j] -= factor * A[k*n + j];
    # Lấy A[i*n + j]
    mul $t1, $t4, $s3       # i * n
    add $t1, $t1, $t5       # i * n + j
    sll $t1, $t1, 2
    add $t3, $s4, $t1       # addr(A[i*n + j])
    l.s $f20, 0($t3)        # $f20 = A[i*n + j]
    
    # Lấy A[k*n + j]
    mul $t1, $t0, $s3       # k * n
    add $t1, $t1, $t5       # k * n + j
    sll $t1, $t1, 2
    add $t6, $s4, $t1       # addr(A[k*n + j])
    l.s $f22, 0($t6)        # $f22 = A[k*n + j]
    
    mul.s $f24, $f18, $f22  # $f24 = factor * A[k*n + j]
    sub.s $f20, $f20, $f24  # $f20 = A[i*n + j] - ...
    s.s $f20, 0($t3)        # Store A[i*n + j]

    addiu $t5, $t5, 1       # j++
    sw $t5, 8($sp)
    j loop_j_elim
end_loop_j_elim:
    
    addiu $t4, $t4, 1       # i++
    sw $t4, 4($sp)
    j loop_i_elim
end_loop_i_elim:

    addiu $t0, $t0, 1       # k++
    sw $t0, 0($sp)
    j loop_k_elim
end_loop_k_elim:

    # ---------------------------------------------------
    # Stage 3: Back substitution (using $s5 = b_copy)
    # ---------------------------------------------------

    # for (int i = n - 1; i >= 0; i--)
    addiu $t0, $s3, -1      # t0 = i = n - 1
    sw $t0, 4($sp)          # Store i
    
loop_i_back:
    lw $t0, 4($sp)          # Load i
    blt $t0, $zero, end_loop_i_back # if i < 0, break

    # float s = b_copy[i];
    sll $t1, $t0, 2         # t1 = i * 4
    add $t1, $s5, $t1       # t1 = addr(b_copy[i]) (using $s5)
    l.s $f10, 0($t1)        # $f10 = s = b_copy[i]

    # for (int j = i + 1; j < n; j++)
    addiu $t2, $t0, 1       # t2 = j = i + 1
    sw $t2, 8($sp)          # Store j
    
loop_j_back:
    lw $t2, 8($sp)          # Load j
    bge $t2, $s3, end_loop_j_back # if j >= n, break

    # s -= A[i*n + j] * solution[j];
    # Extract A[i*n + j]
    mul $t3, $t0, $s3       # i * n
    add $t3, $t3, $t2       # i * n + j
    sll $t3, $t3, 2
    add $t5, $s4, $t3       # addr(A[i*n + j])
    l.s $f12, 0($t5)        # $f12 = A[i*n + j]
    
    # Extract solution[j]
    sll $t3, $t2, 2         # j * 4
    add $t3, $s2, $t3       # addr(solution[j])
    l.s $f14, 0($t3)        # $f14 = solution[j]
    
    mul.s $f16, $f12, $f14  # $f16 = A[i*n+j] * solution[j]
    sub.s $f10, $f10, $f16  # $f10 = s - ...

    addiu $t2, $t2, 1       # j++
    sw $t2, 8($sp)
    j loop_j_back
end_loop_j_back:

    # solution[i] = s / ((fabs(A[i*n+i]) < EPSILON) ? ...);
    # Extract A[i*n + i]
    mul $t3, $t0, $s3       # i * n
    add $t3, $t3, $t0       # i * n + i
    sll $t3, $t3, 2
    add $t5, $s4, $t3       # addr(A[i*n + i])
    l.s $f12, 0($t5)        # $f12 = A[i*n + i]
    
    l.s $f14, EPSILON
    abs.s $f16, $f12
    c.lt.s $f16, $f14       # if (fabs(A[i*n+i]) < EPSILON)
    bc1f back_div_normal    # branch if false
    
    # Case 1: fabs < EPSILON
    add.s $f18, $f12, $f14  # $f18 = A[i*n+i] + EPSILON
    div.s $f20, $f10, $f18  # $f20 = s / ...
    j back_div_done
    
back_div_normal:
    # Case 2: 
    div.s $f20, $f10, $f12  # $f20 = s / A[i*n+i]

back_div_done:
    # Store solution[i] = $f20
    sll $t1, $t0, 2         # t1 = i * 4
    add $t1, $s2, $t1       # t1 = addr(solution[i])
    s.s $f20, 0($t1)

    addiu $t0, $t0, -1      # i--
    sw $t0, 4($sp)
    j loop_i_back
end_loop_i_back:

    lw $s5, 16($sp)
    lw $s4, 20($sp)
    lw $s3, 24($sp)
    lw $s2, 28($sp)
    lw $s1, 32($sp)
    lw $s0, 36($sp)
    
 
    lw $fp, 44($sp)
    lw $ra, 48($sp)
    
  
    addiu $sp, $sp, 52
    
    jr $ra               
