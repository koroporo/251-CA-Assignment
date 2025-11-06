 .data
	input: .asciiz "input.txt"
	desired: .asciiz "desired.txt"
	fileWords: .space 4096
	.align 2
	
	output_file: .asciiz "output.txt"
	output_text: .asciiz "Filtered output: "
	output_mmse: .asciiz "\nMMSE: "
	whitespace: .asciiz " "
	buffer: .space 10
	float_10: .float 10.0
	
	input_signal: .space 40
	desired_signal: .space 40	
	output_signal: .space 40
	optimize_coefficient: .space 404
	mmse: .space 4

	newline: .asciiz "\n"
	ten_float: .float 10.0
	N_limit:	.word	10
	M: .word 101
	maxlag:		.word	50
	autocorr:	.space	404		
	crosscorr:	.space	404
	
	EPSILON: .float 1.0e-8  
    ZERO_S: .float 0.0     
    float_0: .float 0.0
	str_space:	.asciiz " "
	str_err_size: .asciiz "Error: size not match"

.text
.globl main

main:
	# Step 1: Input
	la $a0, input
	la $a1, input_signal		
	jal inputFile
	move $s2, $v0		# $s2 = N_x

	la $a0, desired
	la $a1, desired_signal		
	jal inputFile
	move $s3, $v0		# $s3 = N_d

	bne $s2, $s3, error_size_mismatch # Check for size mismatch

	# Calculae autocorrelation and crosscorrelation
	la	  $a0, input_signal		# $a0 = &x
	move  $a1, $s2				# $a1 = N
	addi	  $a2, $a2, -1		# $a2 = maxlag
	la	  $a3, autocorr		    # $a3 = &autocorr
	jal	  estimate_ac_v2

	la	  $a0, desired_signal	# $a0 = &d
	la	  $a1, input_signal		# $a1 = &x
	move  $a2, $s2				# $a2 = N
	lw	  $a3, maxlag			# $a3 = maxlag
	addi  $sp, $sp, -4
	la	  $t0, crosscorr
	sw	  $t0, 0($sp)
	jal	  estimate_xd_v2
	addi  $sp, $sp, 4
	
	# Solve linear
    la $a0, autocorr     		 # a0 = a (address of autocorr array a)
    la $a1, crosscorr            # a1 = b (address of crosscorr b)
    la $a2, optimize_coefficient # a2 = solution (address of solution array)
    lw $a3, M                    # a3 = M (size)
    move $s0, $a3                # $s0 = M 
    jal solve_linear
	
	# Apply filter
	la $a0, optimize_coefficient
	la $a1, input_signal
	la $a2, output_signal
	lw $a3, M
	jal apply_filter

	# Calculate MMSE
	la $a0, desired_signal
	la $a1, optimize_coefficient
	li $a2, 10
	lw $a3, M
	addi $sp, $sp, -4
	la $t0, crosscorr
	sw $t0, 0($sp)
	jal cal_mmse
	addi $sp, $sp, 4

	# Round up the final numbers
	mov.s $f12, $f0
	jal round
	s.s $f0, mmse
	
	# Print to terminal
	la $a0, output_signal
	li $a1, 10
	l.s $f12, mmse
	jal print_terminal
	
	# Write to File
	la $a0, output_file
	la $a1, output_signal
	li $a2, 10
	l.s $f12, mmse
	jal write_to_file
	
	j exit	

error_size_mismatch:
	li	  $v0, 4
	la	  $a0, str_err_size
	syscall
	
	li $v0, 13
	la $a0, output_file
	li $a1, 1
	li $a2, 0
	syscall
	
	move $s1, $v0
	
	li $v0, 15
	move $a0, $s1
	la $a1, str_err_size
	la $a2, 21
	syscall
	
	li $v0, 16
	move $a0, $s1
	syscall
	
	j exit
	
exit:
	li $v0, 10
	syscall

print_terminal:
	addi $sp, $sp, -12
	sw $s0, 0($sp)
	sw $s1, 4($sp)
	s.s $f13, 8($sp)
	
	move $s0, $a0
	move $s1, $a1
	mov.s $f13, $f12
	
	li $v0, 4
	la $a0, output_text
	syscall
	li $t0, 0
	move $t1, $s0
print_terminal_loop:
	beq $t0, $s1, end_print_terminal
	sll $t2, $t0, 2
	add $t3, $t2, $s0
	l.s $f12, 0($t3)
	li $v0, 2
	syscall
	
	addi $t1, $s1, -1
	bge $t0, $t1, skip_print_space
	
	li $v0, 4
	la $a0, whitespace
	syscall
	
skip_print_space:
	addi $t0, $t0, 1
	j print_terminal_loop
end_print_terminal:
	
	li $v0, 4
	la $a0, output_mmse
	syscall
	
	li $v0, 2
	mov.s $f12, $f13
	syscall
	
	lw $s0, 0($sp)
	lw $s1, 4($sp)
	l.s $f13, 8($sp)
	addi $sp, $sp, 12
	jr $ra

round:
    l.s $f16, float_10
    mul.s $f21, $f12, $f16
    round.w.s $f21, $f21
    cvt.s.w $f21, $f21
    div.s $f0, $f21, $f16
    jr $ra



# -----------------------------------------------------------------
# Function: inputFile
# $a0: Address input file, $a1: Address of the float array
# Trả về: $v0: Số lượng float đọc được
# -----------------------------------------------------------------
inputFile:
	addi $sp, $sp, -20	
	sw $s0, 16($sp)		# s0: file descriptor
	sw $s1, 12($sp)		# s1: number of bytes have read
	sw $a0, 8($sp)		# save &filename
	sw $a1, 4($sp)		# save &array
	sw $s4, 0($sp)		# s4: N_limit = 10

	# Open File
	lw $a0, 8($sp)		
	li $v0, 13
	li $a1, 0
	li $a2, 0
	syscall
	move $s0, $v0		

	# Read File
	li   $v0, 14		
	move $a0, $s0		
	la   $a1, fileWords	
	li   $a2, 4096		# Maximun 256 bytes
	syscall
	move $s1, $v0		
	
	# Close File
	li $v0, 16
	move $a0, $s0
	syscall
	
	# Parse buffer
	lw   $s4, N_limit	
	li $t0, 0			# buffer pointer
	li $t1, 0 			# $t1 = counting float
	li $t2, 0			# integer part
	li $t3, 0			# float part
	li $t9, 0			# is_negative
	li $t5, 0			# has_digit
	li $t6, 0			# is_decimal

parse_loop:
	bge $t1, $s4, store_last_number	
	beq $t0, $s1, store_last_number	
	lb $t7, fileWords($t0)
	
	li $t8, 32						# ' '
	beq $t7, $t8, store_number
	li $t8, 45						# '-'
	beq $t7, $t8, set_neg
	li $t8, 46						# '.'
	beq $t7, $t8, set_decimal
	
	li $t8, 48
	li $t4, 57
	blt $t7, $t8, next_char_parse
	bgt $t7, $t4, next_char_parse
	
	sub $t7, $t7, $t8				# Change char to int
	beq $t6, 0, accumulate_int
	move $t3, $t7					# Save float
	li $t6, 2
	j next_char_parse
accumulate_int:
	mul $t2, $t2, 10
	add $t2, $t2, $t7
	li $t5, 1						
next_char_parse:
	addi $t0, $t0, 1
	j parse_loop
set_neg:
	li $t9, 1			
	addi $t0, $t0, 1
	j parse_loop
set_decimal:
	li $t6, 1			
	addi $t0, $t0, 1
	j parse_loop

store_number:
	bge $t1, $s4, parse_loop_exit	
	beq $t5, 0, skip_store		    
	
	# Combine decimal and integer
	beq $t6, 0, no_decimal
	mul $t2, $t2, 10
	add $t2, $t2, $t3
	j after_decimal
no_decimal:
	mul $t2, $t2, 10
after_decimal:

	beq $t9, 0, store_val
	neg $t2, $t2		# Apply negative
store_val:
	mtc1 $t2, $f0
	cvt.s.w $f0, $f0	# Switch to int 
	l.s $f1, ten_float
	div.s $f0, $f0, $f1	# Div 10.0 
	
	sll $t7, $t1, 2
	lw $t8, 4($sp)		# Load the array address
	add $t8, $t8, $t7
	s.s $f0, 0($t8)		# Store float to array
	
	addi $t1, $t1, 1	# float++
	
	li $t2, 0
	li $t3, 0
	li $t5, 0
	li $t6, 0
	li $t9, 0
	
skip_store:
	addi $t0, $t0, 1
	j parse_loop
	
parse_loop_exit:
	j exit_inputFile

store_last_number:
	bge $t1, $s4, exit_inputFile 
	beq $t5, 0, exit_inputFile 

	beq $t6, 0, no_decimal_last
	mul $t2, $t2, 10
	add $t2, $t2, $t3
	j after_decimal_last
no_decimal_last:
	mul $t2, $t2, 10
after_decimal_last:

	beq $t9, 0, store_val_last
	neg $t2, $t2
store_val_last:
	mtc1 $t2, $f0
	cvt.s.w $f0, $f0
	l.s $f1, ten_float
	div.s $f0, $f0, $f1
	
	sll $t7, $t1, 2
	lw $t8, 4($sp)	
	add $t8, $t8, $t7
	s.s $f0, 0($t8)
	
	addi $t1, $t1, 1	

exit_inputFile:
	move $v0, $t1		# return float ($t1)

	lw $s0, 16($sp)
	lw $s1, 12($sp)
	lw $a0, 8($sp)
	lw $a1, 4($sp)
	lw $s4, 0($sp)		
	addi $sp, $sp, 20
	
	jr $ra

# ---------------------------------------------------------------------
# Function: estimate_ac_v2 (Autocorrelation)
# $a0: &x, $a1: N, $a2: maxlag, $a3: &result_ac
# ---------------------------------------------------------------------
estimate_ac_v2:
	addi  $sp, $sp, -28
	sw	  $ra, 24($sp)
	sw	  $s0, 20($sp)
	sw	  $s1, 16($sp)
	sw	  $s2, 12($sp)
	sw	  $s3, 8($sp)
	sw	  $s4, 4($sp)
	sw	  $s5, 0($sp)
	
	move  $s0, $a0			# s0 = &x
	move  $s1, $a1			# s1 = N
	move  $s2, $a2			# s2 = maxlag
	move  $s3, $a3			# s3 = &result_ac
	
	mtc1  $s1, $f10			# f10 = (float)N
	cvt.s.w $f10, $f10
	
	li	  $s4, 0			# k = 0
outer_loop_ac:
	bgt	  $s4, $s2, end_outer_loop_ac 
	
	move  $s5, $s4			# n = k
	addi  $t1, $s1, -1		# Bound N-1
	
	li	  $t8, 0			
	mtc1  $t8, $f12			
inner_loop_ac:
	bgt	  $s5, $t1, end_inner_loop_ac 
	
	#&x[n]
	sll	  $t2, $s5, 2
	add	  $t3, $s0, $t2	
	
	#&x[n-k]
	sub	  $t4, $s5, $s4
	sll	  $t5, $t4, 2
	add	  $t6, $s0, $t5	
	
	#sum += x[n] * x[n-k]
	l.s	  $f14, 0($t3)
	l.s	  $f16, 0($t6)
	mul.s $f18, $f14, $f16
	add.s $f12, $f12, $f18
	
	addi  $s5, $s5, 1		# n++
	j	  inner_loop_ac
end_inner_loop_ac:
	div.s $f12, $f12, $f10	#sum / N (Biased)
	
	# Store in result_ac[k]
	sll	  $t2, $s4, 2
	add	  $t3, $s3, $t2	
	s.s	  $f12, 0($t3)	
	
	addi  $s4, $s4, 1		# k++
	j	  outer_loop_ac
end_outer_loop_ac:
	# Restore stack
	lw	  $s5, 0($sp)
	lw	  $s4, 4($sp)
	lw	  $s3, 8($sp)
	lw	  $s2, 12($sp)
	lw	  $s1, 16($sp)
	lw	  $s0, 20($sp)
	lw	  $ra, 24($sp)
	addi  $sp, $sp, 28
	jr	  $ra

# ---------------------------------------------------------------------
# Function: estimate_xd_v2 (Cross-correlation - NON-CAUSAL)
# $a0: &d, $a1: &x, $a2: N, $a3: maxlag
# 0($sp): &result_xd
# ---------------------------------------------------------------------
estimate_xd_v2:
	addi  $sp, $sp, -32
	sw	  $ra, 28($sp)
	sw	  $s0, 24($sp)
	sw	  $s1, 20($sp)
	sw	  $s2, 16($sp)
	sw	  $s3, 12($sp)
	sw	  $s4, 8($sp)
	sw	  $s5, 4($sp)
	sw	  $s6, 0($sp)
	
	move  $s0, $a0						# s0 = &d
	move  $s1, $a1						# s1 = &x
	move  $s2, $a2						# s2 = N
	move  $s3, $a3						# s3 = maxlag
	lw	  $s4, 32($sp)					# Load &result_xd to stack
	
	mtc1  $s2, $f10
	cvt.s.w $f10, $f10					# f10 = (float)N
	
	sub $s5, $zero, $s3					# s5 = k = -maxlag
	
outer_loop_xd:
	bgt	  $s5, $s3, end_outer_loop_xd	# For loop k (-maxlag, maxlag)
	li $s6, 0           				# $s6 (start_n) = 0 (if k < 0)
	bgez $s5, skip_lb_k   	
	j skip_lb_k_continue 	
skip_lb_k:
	move $s6, $s5         				# $6 (start_n) = k (if k >= 0)
skip_lb_k_continue:
	addi  $t1, $s2, 0       			# t1 = N
	add $t7, $s2, $s5       			# t7 = N + k
	bge $t7, $t1, skip_ub_k 			# if (N + k >= N) -> end_n = N
	move $t1, $t7         				# else -> end_n = N + k
skip_ub_k:
	# t1 bây giờ chứa min(N, N+k)
	
	li	  $t8, 0			
	mtc1  $t8, $f12						# f12 = sum = 0.0
	
inner_loop_xd:
	bge	  $s6, $t1, end_inner_loop_xd	# For loop n (start_n, end_n)
	
	# &d[n]
	sll	  $t2, $s6, 2
	add	  $t3, $s0, $t2	
	
	# &x[n-k]
	sub	  $t4, $s6, $s5
	sll	  $t5, $t4, 2
	add	  $t6, $s1, $t5	
	
	# sum += d[n] * x[n-k]
	l.s	  $f14, 0($t3)		
	l.s	  $f16, 0($t6)		
	mul.s $f18, $f14, $f16
	add.s $f12, $f12, $f18
	
	addi  $s6, $s6, 1
	j	  inner_loop_xd
end_inner_loop_xd:
	div.s $f12, $f12, $f10				# Sum / N
	
	# Store in result_xd[k + maxlag] 
	add	  $t2, $s5, $s3
	sll	  $t2, $t2, 2
	add	  $t3, $s4, $t2
	s.s	  $f12, 0($t3)
	
	addi  $s5, $s5, 1 					# k++
	j	  outer_loop_xd
end_outer_loop_xd:
	# Restore stack
	lw	  $s6, 0($sp)
	lw	  $s5, 4($sp)
	lw	  $s4, 8($sp)
	lw	  $s3, 12($sp)
	lw	  $s2, 16($sp)
	lw	  $s1, 20($sp)
	lw	  $s0, 24($sp)
	lw	  $ra, 28($sp)
	addi  $sp, $sp, 32
	jr	  $ra
# -----------------------------------------------------------------
# void solve_linear(float* autocorr, float* crosscorr, float* solution, int n)
# -----------------------------------------------------------------
solve_linear:
    # --- Function Prologue ---
    # Cần thêm $s5 để lưu b_copy, nên stack frame lớn hơn
    addiu $sp, $sp, -52     # Cấp phát stack frame (thêm 4 bytes cho $s5)
    sw $ra, 48($sp)         # Lưu thanh ghi trả về
    sw $fp, 44($sp)         # Lưu frame pointer cũ
    addiu $fp, $sp, 48      # Thiết lập frame pointer mới
    
    # Lưu các thanh ghi $s
    sw $s0, 36($sp)
    sw $s1, 32($sp)
    sw $s2, 28($sp)
    sw $s3, 24($sp)
    sw $s4, 20($sp)
    sw $s5, 16($sp)         # Lưu $s5 (sẽ dùng cho b_copy)
    
    # Sao chép đối số vào thanh ghi $s
    move $s0, $a0           # $s0 = a (float* a)
    move $s1, $a1           # $s1 = b (float* b)
    move $s2, $a2           # $s2 = solution (float* solution)
    move $s3, $a3           # $s3 = n

    # float *A = malloc(n * n * sizeof(float));
    mul $a0, $s3, $s3       # $a0 = n * n
    sll $a0, $a0, 2         # $a0 = (n * n) * 4
    li $v0, 9
    syscall
    move $s4, $v0           # $s4 = A (con trỏ float *A liên tục)

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

    # Lấy giá trị a[|i-j|] (từ float** a)
    sub $t3, $t0, $t2         # t3 = i - j
    bgez $t3, skip_abs
    sub $t3, $0, $t3
skip_abs:
	sll $t3, $t3, 2		   # t3 = |i-j|*4
    add $t3, $s0, $t3       # t3 = addr(a[|i-j|])
    l.s $f0, 0($t3)         # $f0 = a[|i-j|]

    # Tính địa chỉ A[i * n + j] (cho float *A)
    mul $t6, $t0, $s3       # t6 = i * n
    add $t6, $t6, $t2       # t6 = i * n + j
    sll $t6, $t6, 2         # t6 = (i * n + j) * 4 (offset)
    add $t6, $s4, $t6       # t6 = addr(A[i*n+j])

    # A[i * n + j] = a[i][j]
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
    sw $t0, 0($sp)          # Lưu k
    
loop_k_elim:
    lw $t0, 0($sp)          # Tải k
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
    sw $t4, 4($sp)          # Lưu i
    
loop_i_pivot:
    lw $t4, 4($sp)          # Tải i
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
    bc1t end_if_pivot       # branch if true (không làm gì)

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
    # (Dùng $s5 = b_copy, thay vì $s1 = b)
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
    # Tải lại A[k*n + k]
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
    lw $t4, 4($sp)          # Tải i
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
    s.s $f20, 0($t1)        # Lưu b_copy[i]

    # for (int j = k; j < n; j++)
    move $t5, $t0           # t5 = j = k
    sw $t5, 8($sp)
    
loop_j_elim:
    lw $t5, 8($sp)          # Tải j
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
    s.s $f20, 0($t3)        # Lưu A[i*n + j]

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
    # PHẦN 3: Thế ngược (dùng $s5 = b_copy)
    # ---------------------------------------------------

    # for (int i = n - 1; i >= 0; i--)
    addiu $t0, $s3, -1      # t0 = i = n - 1
    sw $t0, 4($sp)          # Lưu i
    
loop_i_back:
    lw $t0, 4($sp)          # Tải i
    blt $t0, $zero, end_loop_i_back # if i < 0, break

    # float s = b_copy[i];
    sll $t1, $t0, 2         # t1 = i * 4
    add $t1, $s5, $t1       # t1 = addr(b_copy[i]) (dùng $s5)
    l.s $f10, 0($t1)        # $f10 = s = b_copy[i]

    # for (int j = i + 1; j < n; j++)
    addiu $t2, $t0, 1       # t2 = j = i + 1
    sw $t2, 8($sp)          # Lưu j
    
loop_j_back:
    lw $t2, 8($sp)          # Tải j
    bge $t2, $s3, end_loop_j_back # if j >= n, break

    # s -= A[i*n + j] * solution[j];
    # Lấy A[i*n + j]
    mul $t3, $t0, $s3       # i * n
    add $t3, $t3, $t2       # i * n + j
    sll $t3, $t3, 2
    add $t5, $s4, $t3       # addr(A[i*n + j])
    l.s $f12, 0($t5)        # $f12 = A[i*n + j]
    
    # Lấy solution[j]
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
    # Lấy A[i*n + i]
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
    # Case 2: Chia bình thường
    div.s $f20, $f10, $f12  # $f20 = s / A[i*n+i]

back_div_done:
    # Lưu solution[i] = $f20
    sll $t1, $t0, 2         # t1 = i * 4
    add $t1, $s2, $t1       # t1 = addr(solution[i])
    s.s $f20, 0($t1)

    addiu $t0, $t0, -1      # i--
    sw $t0, 4($sp)
    j loop_i_back
end_loop_i_back:

    # Note that we cannot free dynamically allocated data in MIPS Assembly
    lw $s5, 16($sp)
    lw $s4, 20($sp)
    lw $s3, 24($sp)
    lw $s2, 28($sp)
    lw $s1, 32($sp)
    lw $s0, 36($sp)
    
    lw $fp, 44($sp)
    lw $ra, 48($sp)
    
    addiu $sp, $sp, 52
    
    jr $ra                  # Trở về hàm gọi (main)
    
# Applies the Wiener filter to the input
# Arguments: $a0: address of array of Wiener coefficients, $a1: address of input array, $a2: address of output array, $a3: order of filter
apply_filter:
	addi $sp, $sp, -44
	sw $s0, 0($sp)
	sw $s1, 4($sp)
	sw $s2, 8($sp)
	sw $s3, 12($sp)
	sw $t0, 16($sp) 		# SỬA LỖI: Xóa dấu phẩy
	sw $t1, 20($sp)
	sw $t2, 24($sp)
	sw $t3, 28($sp)
	sw $t4, 32($sp)
	sw $ra, 36($sp)
	sw $s4, 40($sp)
	
	move $s0, $a0 # s0 = &w (h)
	move $s1, $a1 # s1 = &x
	move $s2, $a2 # s2 = &y
	move $s3, $a3 # s3 = M (order)
	
	# Tính delay = (M - 1) / 2
	move $s4, $s3
	addi $s4, $s4, -1
	divu $s4, $s4, 2 # s4 = delay
	
	lw $t5, N_limit # t5 = N (ví dụ: 10)
	
	li $t0, 0 # n = 0
n_loop:
	beq $t0, $t5, end_n_loop # Lặp N lần (0 đến N-1)
	
	l.s $f0, float_0 # f0 = y[n] = 0.0
	li $t1, 0 # k = 0
k_loop:
	beq $t1, $s3, end_k_loop # Lặp M lần (0 đến M-1)
	
	# Tính idx = n - k + delay
	sub $t2, $t0, $t1		 # n - k
	add $t2, $t2, $s4		 # t2 = idx = (n - k) + delay
	
	# Kiểm tra biên: if (idx < 0) or (idx >= N)
	bltz $t2, continue_k_loop 
	bge $t2, $t5, continue_k_loop # SỬA LỖI: Dùng $t5 (N) thay vì 10
	
	# --- Chỉ thực hiện nếu idx nằm trong biên ---
	# Tải w[k]
	sll $t3, $t1, 2			 # t3 = k * 4	
	add $t4, $t3, $s0		 # address of w[k]
	l.s $f1, 0($t4)
	
	# Tải x[idx]
	sll $t3, $t2, 2			 # t3 = idx * 4
	add $t4, $t3, $s1		 # address of x[idx]
	l.s $f2, 0($t4)

	mul.s $f3, $f1, $f2		 # f3 = w[k] * x[idx]
	add.s $f0, $f0, $f3		 # y[n] += ...
	# --- Hết khối if ---

continue_k_loop:
	addi $t1, $t1, 1 # k++
	j k_loop
end_k_loop:

	# SỬA LỖI: Xóa hàm round không cần thiết
	mov.s $f12, $f0
	jal round
	
	# Lưu y[n]
	sll $t3, $t0, 2
	add $t4, $t3, $s2
	s.s $f0, 0($t4)			 # save to y[n]
	
	addi $t0, $t0, 1 # n++
	j n_loop
end_n_loop:

	lw $s0, 0($sp)
	lw $s1, 4($sp)
	lw $s2, 8($sp)
	lw $s3, 12($sp)
	lw $t0, 16($sp)
	lw $t1, 20($sp)
	lw $t2, 24($sp)
	lw $t3, 28($sp)
	lw $t4, 32($sp)
	lw $ra, 36($sp)
	lw $s4, 40($sp)
	addi $sp, $sp, 44
	jr $ra
	
# Calculates the mmse value
# Arguments: $a0: address of desired values, $a1: address of coefficients, $a2: size of values, $a3: order of filter
# Returns: $f0: the mmse value
cal_mmse:
	lw $t0, 0($sp)
	
	addi $sp, $sp, -20
	sw $s0, 0($sp)
	sw $s1, 4($sp)
	sw $s2, 8($sp)
	sw $s3, 12($sp)
	sw $s4, 16($sp)
	
	move $s0, $a0	# s0 = address of desired
	move $s1, $a1	# s1 = address of coefficients
	move $s2, $a2	# s2 = value size 
	move $s3, $a3	# s3 = filter order
	move $s4, $t0
	
	l.s $f0, float_0
	
	# Calculate the variance
	li $t0, 0
variance_loop:
	beq $t0, $s2, end_variance
	sll $t1, $t0, 2
	add $t2, $t1, $s0
	l.s $f1, 0($t2)
	mul.s $f1, $f1, $f1
	add.s $f0, $f0, $f1
	addi $t0, $t0, 1
	j variance_loop
end_variance:
	mtc1 $s2, $f2
	cvt.s.w $f2, $f2
	div.s $f0, $f0, $f2
	
	li $t0, 0
subtract_loop:
	beq $t0, $s3, end_subtract_loop
	sll $t1, $t0, 2
	add $t2, $t1, $s4
	l.s $f1, 0($t2)
	
	add $t2, $t1, $s1
	l.s $f2, 0($t2)
	
	mul.s $f1, $f1, $f2
	sub.s $f0, $f0, $f1
	addi $t0, $t0, 1
	j subtract_loop
end_subtract_loop:
	lw $s0, 0($sp)
	lw $s1, 4($sp)
	lw $s2, 8($sp)
	lw $s3, 12($sp)
	lw $s4, 16($sp)
	addi $sp, $sp, 20
	jr $ra
	
# Writes the output to a file
# Arguments: $a0: string containing file name, $a1: array of floats, $a2: size of array, $f12: mmse
# Returns: N/A
write_to_file:
	addi $sp, $sp, -20
	sw $s0, 0($sp)
	sw $s1, 4($sp)
	sw $s2, 8($sp)
	sw $s3, 12($sp)
	sw $ra, 16($sp)
	
	move $s0, $a0
	move $s1, $a1
	move $s2, $a2
	mov.s $f13, $f12
	
	li $v0, 13
	move $a0, $s0
	li $a1, 1
	li $a2, 0
	syscall
	move $s3, $v0 #file descriptor
	
	
	li $v0, 15
	move $a0, $s3
	la $a1, output_text
	li $a2, 17
	syscall
	
	li $t0, 0
write_loop:
	bge $t0, $s2, end_loop
	sll $t1, $t0, 2
	add $t1, $s1, $t1
	l.s $f12, 0($t1)
	la $a0, buffer
	addi $sp, $sp, -4
	sw $t0, 0($sp)
	jal ftoa
	lw $t0, 0($sp)
	addi $sp, $sp, 4
	move $t2, $v0 #$t2 contains string to write
	move $t3, $v1 #$t3 contains string length
	
	li $v0, 15
	move $a0, $s3
	move $a1, $t2
	move $a2, $t3
	syscall
	
	addi $t0, $t0, 1
	beq $t0, $s2, skip_space
	li $v0, 15
	move $a0, $s3
	la $a1, whitespace
	li $a2, 1
	syscall
skip_space:
	j write_loop
	
end_loop:
	li $v0, 15
	move $a0, $s3
	la $a1, output_mmse
	li $a2, 7
	syscall
	
	la $a0, buffer
	mov.s $f12, $f13
	jal ftoa
	
	move $t2, $v0
	move $t3, $v1
	
	li $v0, 15
	move $a0, $s3
	move $a1, $t2
	move $a2, $t3
	syscall
	
	li $v0, 16
	move $a0, $s3
	syscall
	
	lw $s0, 0($sp)
	lw $s1, 4($sp)
	lw $s2, 8($sp)
	lw $s3, 12($sp)
	lw $ra, 16($sp)
	addi $sp, $sp, 20
	jr $ra
# Reverse a string
# Arguments: $a0: string to reverse, $a1: length of string
# Returns: $v0: the address of the reversed string
reverse:
	addi $sp, $sp, -4
	sw $s0, 0($sp)
	add $s0, $0, $a0
	add $t0, $0, 0 # i = 0
	addi $t1, $a1, -1 # j = len-1
reverse_loop:
	bge $t0, $t1, end_reverse
	add $t2, $s0, $t0 # str[i]
	lbu $t3, 0($t2)
	add $t4, $s0, $t1 #str[j]]
	lbu $t5, 0($t4)
	sb $t5, 0($t2)
	sb $t3, 0($t4)
	addi $t0, $t0, 1
	addi $t1, $t1, -1
	j reverse_loop
end_reverse:
	add $v0, $0, $s0
	lw $s0, 0($sp)
	addi $sp, $sp, 4
	jr $ra

# Converts an integer to a string of specified length
# Arguments: $a0: integer to be converted, $a1: address of resulting string, $a2: length of string (if longer, pad with zeros; if 0, no restrictions)
# Returns: $v0: address of resulting string, $v1: length of string
int_to_str:
	addi $sp, $sp, -12
	sw $s0, 0($sp)
	sw $s1, 4($sp)
	sw $ra, 8($sp)

	add $s0, $0, $a1      # destination buffer
	li $s1, 0             # counter = 0
	li $t1, 10            # divisor = 10
	move $t0, $a0         # copy integer to t0

	beqz $t0, write_zero

int_loop:
	beqz $t0, end_int_loop
	div $t0, $t1
	mflo $t0
	mfhi $t3
	addi $t3, $t3, 48
	sb $t3, 0($s0)
	addi $s0, $s0, 1
	addi $s1, $s1, 1
	j int_loop

write_zero:
	li $t3, 48
	sb $t3, 0($s0)
	addi $s0, $s0, 1
	addi $s1, $0, 1

end_int_loop:
# zero padding
loop_pad:
	bge $s1, $a2, pad_done
	li $t3, 48
	sb $t3, 0($s0)
	addi $s0, $s0, 1
	addi $s1, $s1, 1
	j loop_pad

pad_done:
	sb $zero, 0($s0)         # null terminate
	sub $a0, $s0, $s1        # start address
	move $a1, $s1            # length
	jal reverse

	move $v0, $a0
	move $v1, $a1

	lw $s0, 0($sp)
	lw $s1, 4($sp)
	lw $ra, 8($sp)
	addi $sp, $sp, 12
	jr $ra

# Converts a floating point number with 1 decimal place precision to string
# Arguments: $f12, floating point number to convert (precondition: must have 1 decimal place of precision)
#            $a0, address of string
# Returns: $v0: address of resulting string, $v1: length of resulting string
ftoa:
	addi $sp, $sp, -20
	sw $s0, 0($sp)
	sw $s1, 4($sp)
	sw $s2, 8($sp)
	sw $s3, 12($sp)
	sw $ra, 16($sp)
	
	
	move $s0, $a0
	move $s2, $s0 # lưu lại địa chỉ buffer gốc
	li $s3, 0
	l.s $f4, float_0
	c.lt.s $f12, $f4
	bc1f skip_negative
	
	# Xử lý dấu âm
	addi $t0, $0, 45
	sb $t0, 0($s0)
	addi $s0, $s0, 1
	addi $s3, $s3, 1
	neg.s $f12, $f12
skip_negative:
	
	# --- SỬA LỖI 1: Tách phần nguyên và thập phân ---
	trunc.w.s $f1, $f12 	# $f1 = phần nguyên (dạng int)
	cvt.s.w $f3, $f1		# $f3 = phần nguyên (dạng float)
	sub.s $f2, $f12, $f3 	# $f2 = phần thập phân (vd: 0.4)
	mfc1 $t0, $f1 			# $t0 = phần nguyên (dạng int)
	# --- Hết Sửa 1 ---

	move $a0, $t0			# a0 = phần nguyên
	move $a1, $s0
	li $a2 0
	jal int_to_str
	
	move $s0, $v0
	move $s1, $v1 # $s1 = độ dài phần nguyên
	
	add $t0, $s0, $s1 # $t0 = con trỏ sau phần nguyên
	li $t1, 46
	sb $t1, 0($t0) # viết dấu '.'
	
	# --- SỬA LỖI 2: Tính toán phần thập phân ---
	l.s $f3, float_10
	mul.s $f2, $f2, $f3 	# $f2 = phần thập phân * 10
	round.w.s $f2, $f2		# làm tròn (vd: 0.4*10 = 4.0)
	mfc1 $t1, $f2 			# $t1 = số thập phân (vd: 4)
	# --- Hết Sửa 2 ---
	
	move $a0, $t1
	addi $a1, $t0, 1		# con trỏ sau dấu '.'
	li $a2, 1				# luôn in 1 chữ số
	jal int_to_str
	
	move $v0, $s2
	add $v1, $v1, $s1		# tổng độ dài = (độ dài .0) + (độ dài phần nguyên)
	addi $v1, $v1, 1		# + 1 cho dấu '.'
	add $v1, $v1, $s3		# + 1 cho dấu '-' (nếu có)
	
	lw $s0, 0($sp)
	lw $s1, 4($sp)
	lw $s2, 8($sp)
	lw $s3, 12($sp)
	lw $ra, 16($sp)
	addi $sp, $sp, 20
	jr $ra
