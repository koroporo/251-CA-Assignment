.data
	# --- Định nghĩa file và bộ đệm ---
	input: .asciiz "input.txt"
	desired: .asciiz "desired.txt"
	fileWords: .space 512
	.align 2
	
	# --- Các biến theo yêu cầu bài tập ---
	input_signal: .space 40		# Mảng 10 float cho input
	desired_signal: .space 40	# Mảng 10 float cho desired

	# --- Hằng số và chuỗi ---
	newline: .asciiz "\n"
	ten_float: .float 10.0
	N_limit:	.word	10		
	maxlag:		.word	5		
	result_ac:	.space	24		
	result_xd:	.space	24		
	
	str_ac:		.asciiz "--- Autocorrelation (AC) ---\n"
	str_xd:		.asciiz "\n--- Cross-correlation (XD) ---\n"
	str_space:	.asciiz " "
	str_err_size: .asciiz "Error: size not match"

.text
.globl main

main:
	# --- Đọc file input.txt ---
	la $a0, input
	la $a1, input_signal		
	jal inputFile
	move $s2, $v0				# $s2 = N (số lượng từ input.txt)

	# --- Đọc file desired.txt ---
	la $a0, desired
	la $a1, desired_signal		
	jal inputFile
	move $s3, $v0				# $s3 = N_d (số lượng từ desired.txt)

	# --- Kiểm tra lỗi size (theo yêu cầu PDF) ---
	bne $s2, $s3, error_size_mismatch

	# --- Gọi hàm tính Autocorrelation ---
	la	  $a0, input_signal		# a0 = &x
	move  $a1, $s2				# a1 = N
	lw	  $a2, maxlag			# a2 = maxlag
	la	  $a3, result_ac		# a3 = &result_ac
	jal	  estimate_ac_v2

	# --- Gọi hàm tính Cross-correlation ---
	la	  $a0, desired_signal	# a0 = &d
	la	  $a1, input_signal		# a1 = &x
	move  $a2, $s2				# a2 = N
	lw	  $a3, maxlag			# a3 = maxlag
	
	# Truyền &result_xd qua stack
	addi  $sp, $sp, -4
	la	  $t0, result_xd
	sw	  $t0, 0($sp)
	jal	  estimate_xd_v2
	addi  $sp, $sp, 4			

	# --- In kết quả AC ---
	la	  $a0, str_ac
	li	  $v0, 4
	syscall
	
	la	  $a0, result_ac
	lw	  $a1, maxlag
	addi  $a1, $a1, 1			# a1 = số lượng phần tử = maxlag + 1
	jal	  print_float_array
	
	# --- In kết quả XD ---
	la	  $a0, str_xd
	li	  $v0, 4
	syscall
	
	la	  $a0, result_xd
	lw	  $a1, maxlag
	addi  $a1, $a1, 1
	jal	  print_float_array
	
	j	  exit				

error_size_mismatch:
	li	  $v0, 4
	la	  $a0, str_err_size
	syscall
	
exit:
	li $v0, 10
	syscall

# -----------------------------------------------------------------
# HÀM: inputFile
# $a0: Địa chỉ tên file, $a1: Địa chỉ mảng float
# Trả về: $v0: Số lượng float đọc được
# -----------------------------------------------------------------
inputFile:
	addi $sp, $sp, -20	
	sw $s0, 16($sp)		# s0: file descriptor
	sw $s1, 12($sp)		# s1: số byte đã đọc
	sw $a0, 8($sp)		# lưu &filename
	sw $a1, 4($sp)		# lưu &array
	sw $s4, 0($sp)		# s4: N_limit (giới hạn 10)

	# STAGE 1: MỞ FILE
	lw $a0, 8($sp)		
	li $v0, 13
	li $a1, 0
	li $a2, 0
	syscall
	move $s0, $v0		

	# STAGE 2: ĐỌC FILE
	li   $v0, 14		
	move $a0, $s0		
	la   $a1, fileWords	
	li   $a2, 256		# Đọc tối đa 256 bytes
	syscall
	move $s1, $v0		
	
	# STAGE 3: ĐÓNG FILE
	li $v0, 16
	move $a0, $s0
	syscall
	
	# STAGE 4: PARSE BUFFER
	lw   $s4, N_limit	# $s4 = 10 (giới hạn)
	li $t0, 0			# con trỏ buffer
	li $t1, 0 			# $t1 = đếm số float
	li $t2, 0			# phần nguyên
	li $t3, 0			# phần thập phân
	li $t9, 0			# cờ âm (is_negative)
	li $t5, 0			# cờ đã đọc số (has_digit)
	li $t6, 0			# cờ dấu chấm (is_decimal)

parse_loop:
	bge $t1, $s4, store_last_number	# Nếu đã đủ 10 số, nhảy
	beq $t0, $s1, store_last_number	# Nếu hết buffer, nhảy
	lb $t7, fileWords($t0)
	
	li $t8, 45			# '-'
	beq $t7, $t8, set_neg
	li $t8, 32			# ' '
	beq $t7, $t8, store_number
	li $t8, 46			# '.'
	beq $t7, $t8, set_decimal
	
	# Kiểm tra nếu là ký tự số '0'-'9'
	li $t8, 48
	li $t4, 57
	blt $t7, $t8, next_char_parse
	bgt $t7, $t4, next_char_parse
	
	sub $t7, $t7, $t8	# Chuyển '0'->0
	beq $t6, 0, accumulate_int
	move $t3, $t7		# Lưu 1 số thập phân
	li $t6, 2
	j next_char_parse
accumulate_int:
	mul $t2, $t2, 10
	add $t2, $t2, $t7
	li $t5, 1			# Đánh dấu đã đọc số
next_char_parse:
	addi $t0, $t0, 1
	j parse_loop
set_neg:
	li $t9, 1			# set is_negative = true
	addi $t0, $t0, 1
	j parse_loop
set_decimal:
	li $t6, 1			# set is_decimal = true
	addi $t0, $t0, 1
	j parse_loop

store_number:
	bge $t1, $s4, parse_loop_exit	# Nếu 10 số thì thoát
	beq $t5, 0, skip_store		# Nếu không có số, bỏ qua
	
	# Kết hợp phần nguyên và 1 số thập phân
	beq $t6, 0, no_decimal
	mul $t2, $t2, 10
	add $t2, $t2, $t3
	j after_decimal
no_decimal:
	mul $t2, $t2, 10
after_decimal:

	beq $t9, 0, store_val
	neg $t2, $t2		# Áp dụng dấu âm
store_val:
	mtc1 $t2, $f0
	cvt.s.w $f0, $f0	# Chuyển int 
	l.s $f1, ten_float
	div.s $f0, $f0, $f1	# Chia 10.0 
	
	sll $t7, $t1, 2
	lw $t8, 4($sp)		# lấy địa chỉ mảng
	add $t8, $t8, $t7
	s.s $f0, 0($t8)		# Lưu float vào mảng
	
	addi $t1, $t1, 1	# Tăng biến đếm số float
	
	# Reset các biến tạm
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
	bge $t1, $s4, exit_inputFile #Nếu 10 số thì thoát
	beq $t5, 0, exit_inputFile # Không có số, thoát

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
	move $v0, $t1		# Trả về số lượng float ($t1)

	lw $s0, 16($sp)
	lw $s1, 12($sp)
	lw $a0, 8($sp)
	lw $a1, 4($sp)
	lw $s4, 0($sp)		
	addi $sp, $sp, 20
	
	jr $ra

# ---------------------------------------------------------------------
# HÀM: estimate_ac_v2 (Autocorrelation)
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
	bgt	  $s4, $s2, end_outer_loop_ac # Vòng lặp ngoài (k)
	
	move  $s5, $s4			# n = k
	addi  $t1, $s1, -1		# Giới hạn N-1
	
	li	  $t8, 0			# SỬA LỖI: f12 = 0.0
	mtc1  $t8, $f12			
inner_loop_ac:
	bgt	  $s5, $t1, end_inner_loop_ac # Vòng lặp trong (n)
	
	# Tính địa chỉ &x[n]
	sll	  $t2, $s5, 2
	add	  $t3, $s0, $t2	
	
	# Tính địa chỉ &x[n-k]
	sub	  $t4, $s5, $s4
	sll	  $t5, $t4, 2
	add	  $t6, $s0, $t5	
	
	# Tính sum += x[n] * x[n-k]
	l.s	  $f14, 0($t3)
	l.s	  $f16, 0($t6)
	mul.s $f18, $f14, $f16
	add.s $f12, $f12, $f18
	
	addi  $s5, $s5, 1		# n++
	j	  inner_loop_ac
end_inner_loop_ac:
	# Chuẩn hóa: sum / N (Biased)
	div.s $f12, $f12, $f10	
	
	# Lưu kết quả vào result_ac[k]
	sll	  $t2, $s4, 2
	add	  $t3, $s3, $t2	
	s.s	  $f12, 0($t3)	
	
	addi  $s4, $s4, 1		# k++
	j	  outer_loop_ac
end_outer_loop_ac:
	# Khôi phục stack
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
# HÀM: estimate_xd_v2 (Cross-correlation)
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
	
	move  $s0, $a0			# s0 = &d
	move  $s1, $a1			# s1 = &x
	move  $s2, $a2			# s2 = N
	move  $s3, $a3			# s3 = maxlag
	lw	  $s4, 32($sp)		# nạp &result_xd từ stack
	
	mtc1  $s2, $f10
	cvt.s.w $f10, $f10		# f10 = (float)N
	
	li	  $s5, 0			# k = 0
outer_loop_xd:
	bgt	  $s5, $s3, end_outer_loop_xd # Vòng lặp ngoài (k)
	
	move  $s6, $s5			# n = k
	addi  $t1, $s2, -1		# Giới hạn N-1
	
	li	  $t8, 0			
	mtc1  $t8, $f12			
inner_loop_xd:
	bgt	  $s6, $t1, end_inner_loop_xd # Vòng lặp trong (n)
	
	# Tính địa chỉ &d[n] (KHÁC BIỆT 1)
	sll	  $t2, $s6, 2
	add	  $t3, $s0, $t2	
	
	# Tính địa chỉ &x[n-k] (Giống hệt)
	sub	  $t4, $s6, $s5
	sll	  $t5, $t4, 2
	add	  $t6, $s1, $t5	
	
	# Tính sum += d[n] * x[n-k] (KHÁC BIỆT 2)
	l.s	  $f14, 0($t3)		# f14 = d[n]
	l.s	  $f16, 0($t6)		# f16 = x[n-k]
	mul.s $f18, $f14, $f16
	add.s $f12, $f12, $f18
	
	addi  $s6, $s6, 1
	j	  inner_loop_xd
end_inner_loop_xd:
	# Chuẩn hóa: sum / N
	div.s $f12, $f12, $f10	
	
	# Lưu kết quả vào result_xd[k]
	sll	  $t2, $s5, 2
	add	  $t3, $s4, $t2
	s.s	  $f12, 0($t3)
	
	addi  $s5, $s5, 1
	j	  outer_loop_xd
end_outer_loop_xd:
	# Khôi phục stack
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

# ---------------------------------------------------------------------
# HÀM: print_float_array (Hàm tiện ích)
# $a0: &array, $a1: size
# ---------------------------------------------------------------------
print_float_array:
	move  $t0, $a0			# t0 = con trỏ mảng
	move  $t1, $a1			# t1 = số lượng
	li	  $t2, 0			# i = 0
print_loop:
	beq	  $t2, $t1, end_print_loop 
	l.s	  $f12, 0($t0)		
	li	  $v0, 2			# syscall 2: print float
	syscall
	
	la	  $a0, str_space
	li	  $v0, 4
	syscall
	
	addi  $t0, $t0, 4		
	addi  $t2, $t2, 1		
	j	  print_loop
end_print_loop:
	la	  $a0, newline		
	li	  $v0, 4
	syscall
	jr	  $ra
