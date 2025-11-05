.data
	output_file: .asciiz "output.txt"
	output_signal: .float 1.0, 2.0, 3.0, 4.0, 5.0, 8.0, -1.4, 9.3, -123.1, 12.0
	output_text: .asciiz "Filtered output: "
	output_mmse: .asciiz "\nMMSE: "
	whitespace: .asciiz " "
	buffer: .space 10
	float_10: .float 10.0
	float_0: .float 0.0
	mmse: .float 123.1
.text
main:
	la $a0, output_file
	la $a1, output_signal
	li $a2, 10
	l.s $f12, mmse
	jal write_to_file

exit:
	li $v0, 10
	syscall
# Writes the output to a file
# Arguments: $a0: string containing file name, $a1: array of floats, $a2: size of array, $f12: mmse
# Returns: N/A
write_to_file:
	addi $sp, $sp, -24
	sw $s0, 0($sp)
	sw $s1, 4($sp)
	sw $s2, 8($sp)
	sw $s3, 12($sp)
	sw $s4, 16($sp)
	sw $ra, 20($sp)
	
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
	
	li $s4, 0
	
	li $v0, 15
	move $a0, $s3
	la $a1, output_text
	li $a2, 17
	syscall
write_loop:
	bge $s4, $s2, end_loop
	sll $t1, $s4, 2
	add $t1, $s1, $t1
	l.s $f12, 0($t1)
	la $a0, buffer
	jal ftoa
	move $t2, $v0 #$t2 contains string to write
	move $t3, $v1 #$t3 contains string length
	
	li $v0, 15
	move $a0, $s3
	move $a1, $t2
	move $a2, $t3
	syscall
	
	addi $s4, $s4, 1
	beq $s4, $s2, skip_space
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
	lw $s4, 16($sp)
	lw $ra, 20($sp)
	addi $sp, $sp, 24
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
	
	
	add $s0, $0, $a0
	add $s2, $s0, $0 # preserves a copy of the address
	addi $s3, $0, 0
	l.s $f4, float_0
	c.lt.s $f12, $f4
	bc1f skip_negative
	addi $t0, $0, 45
	sb $t0, 0($s0)
	addi $s0, $s0, 1
	addi $s3, $s3, 1
	neg.s $f12, $f12
skip_negative:
	trunc.w.s $f1, $f12 # int part
	cvt.s.w $f3, $f1
	sub.s $f2, $f12, $f3 # float part
	mfc1 $t0, $f1 # $t0 now holds the integer part
	
	add $a0, $0, $t0
	add $a1, $0, $s0
	addi $a2, $0, 0
	jal int_to_str
	
	move $s0, $v0
	move $s1, $v1
	
	add $t0, $s0, $s1 # $t0 = res + i
	addi $t1, $0, 46
	sb $t1, 0($t0)
	
	l.s $f3, float_10
	mul.s $f2, $f2, $f3 
	round.w.s $f2, $f2
	mfc1 $t1, $f2 #calculate the floating point part
	
	add $a0, $0, $t1
	addi $a1, $t0, 1
	addi $a2, $0, 1
	jal int_to_str
	
	move $v0, $s2
	add $v1, $v1, $s1
	addi $v1, $v1, 1
	add $v1, $v1, $s3
	lw $s0, 0($sp)
	lw $s1, 4($sp)
	lw $s2, 8($sp)
	lw $s3, 12($sp)
	lw $ra, 16($sp)
	addi $sp, $sp, 20
	jr $ra
