.data
	optimize_coefficient: .float 0.7099, -0.0319, -0.0101
	input_signal: .float 1, 2, 0.5, 1
	desired_signal: .float 0.5, 1.5, 0.2, 0.7
	output_signal: .space 16
	crosscorr: .float 1.075, 0.5625, 0.4
	newline: .asciiz "\n"
	M: .word 3
	N: .word 4
	MMSE: .space 4
	float_0: .float 0.0
.text
	la $a0, optimize_coefficient
	la $a1, input_signal
	la $a2, output_signal
	lw $a3, M
	jal apply_filter
	
	la $a0, desired_signal
	la $a1, optimize_coefficient
	li $a2, 4
	lw $a3, M
	jal mmse
	
	li $v0, 2
	mov.s $f12, $f0
	syscall
	
	li $v0, 4
	la $a0, newline
	syscall
	
print_floats:
    li $t3, 0             # Loop counter i = 0

print_loop:
    bge $t3, 4, done    # Use the saved count in $s2 as the loop limit

    # Calculate address of input_signal[i]
    sll $t7, $t3, 2
    la $t8, output_signal  # Use the new array name
    add $t8, $t8, $t7
    lwc1 $f12, 0($t8)     # Load float into $f12 for printing

    li $v0, 2
    syscall               # Print float
    
    li $v0, 4
    la $a0, newline
    syscall               # Print newline

    addi $t3, $t3, 1      # i++
    j print_loop
done:
	li $v0, 10
	syscall

# Applies the Wiener filter to the input
# Arguments: $a0: address of array of Wiener coefficients, $a1: address of input array, $a2: address of output array, $a3: order of filter
apply_filter:
	addi $sp, $sp, -36
	sw $s0, 0($sp)
	sw $s1, 4($sp)
	sw $s2, 8($sp)
	sw $s3, 12($sp)
	sw $t0, 16, ($sp)
	sw $t1, 20($sp)
	sw $t2, 24($sp)
	sw $t3, 28($sp)
	sw $t4, 32($sp)
	
	move $s0, $a0
	move $s1, $a1
	move $s2, $a2
	move $s3, $a3  # s3 = order of filter
	
	addi $t0, $0, 0
n_loop:
	beq $t0, 4, end_n_loop
	l.s $f0, float_0
	addi $t1, $0, 0 # n
k_loop:
	beq, $t1, $a3, end_k_loop
	sub $t2, $t0, $t1        # n - k
	bltz $t2, end_k_loop     # if n - k < 0, break inner loop
	sll $t3, $t1, 2          # t3 = k * 4 
	add $t4, $t3, $s0        # address of h[k]
	l.s $f1, 0($t4)
	
	sll $t3, $t2, 2          # t3 = (n - k) * 4
	add $t4, $t3, $s1        # address of x[n-k]
	l.s $f2, 0($t4)

	mul.s $f3, $f1, $f2      # f3 = h[k] * x[n-k]
	add.s $f0, $f0, $f3      # y[n] += h[k] * x[n-k]
	addi $t1, $t1, 1
	j k_loop
end_k_loop:
	sll $t3, $t0, 2
	add $t4, $t3, $s2
	s.s $f0, 0($t4)          # save to y[n]
	addi $t0, $t0, 1
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
	addi $sp, $sp, 36
	jr $ra
	
# Calculates the mmse value
# Arguments: $a0: address of desired values, $a1: address of coefficients, $a2: size of values, $a3: order of filter
# Returns: $f0: the mmse value
mmse:
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
	la $s4, crosscorr
	
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