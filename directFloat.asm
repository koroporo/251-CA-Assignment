.data
fileName:   .asciiz "input.txt" # Make sure this path is correct
fileWords:  .space 8192        # buffer for file content
.align 2
int_array:  .space 2000        # Original array: 1000 integers (4 bytes each)
float_array:.space 2000        # ADDED: New array to store actual floats
newline:    .asciiz "\n"

ten_float:  .float 10.0        # ADDED: The float value 10.0 for division

.text
.globl main

main:
    # --- OPEN FILE FOR READING ---
    # (This section is unchanged)
    li $v0, 13
    la $a0, fileName
    li $a1, 0           # read mode
    li $a2, 0
    syscall
    move $s0, $v0       # file descriptor

    # --- READ FILE ---
    # (This section is unchanged)
    li $v0, 14
    move $a0, $s0
    la $a1, fileWords
    li $a2, 8192        # buffer size (was 16384, 4096 is likely enough)
    syscall
    move $s1, $v0       # number of bytes read

    # --- CLOSE FILE ---
    # (This section is unchanged)
    li $v0, 16
    move $a0, $s0
    syscall

    # --- PARSE FLOAT NUMBERS INTO ARRAY ---
    # (This parsing logic is unchanged)
    li $t0, 0       # buffer index
    li $t1, 0       # array index
    li $t2, 0       # accumulator for integer part
    li $t3, 0       # decimal digit
    li $t9, 0       # neg_flag
    li $t5, 0       # number_pending flag
    li $t6, 0       # decimal_flag (0=no decimal, 1=decimal seen)

parse_loop:
    beq $t0, $s1, store_last_number

    lb $t7, fileWords($t0)
    li $t8, 45
    beq $t7, $t8, set_neg
    li $t8, 32
    beq $t7, $t8, store_number
    li $t8, 46
    beq $t7, $t8, set_decimal
    li $t8, 48
    li $t4, 57
    blt $t7, $t8, next_char_parse
    bgt $t7, $t4, next_char_parse
    sub $t7, $t7, $t8
    beq $t6, 0, accumulate_int
    move $t3, $t7
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
    beq $t5, 0, skip_store

    # combine integer and decimal (unchanged)
    beq $t6, 0, no_decimal
    mul $t2, $t2, 10
    add $t2, $t2, $t3
    j after_decimal
no_decimal:
    mul $t2, $t2, 10
after_decimal:
    # apply negative sign (unchanged)
    beq $t9, 0, store_val
    neg $t2, $t2
store_val:
    sll $t7, $t1, 2
    la $t8, int_array
    add $t8, $t8, $t7
    sw $t2, 0($t8)

    # ==========================================================
    # --- MODIFICATION: Convert to float and store in new array ---
    # Now that the integer version (e.g., 123) is in $t2,
    # convert it to a float and store it in float_array.
    
    # 1. Move integer from CPU register to FPU register
    mtc1 $t2, $f0
    
    # 2. Convert the integer in $f0 to a single-precision float
    cvt.s.w $f0, $f0        # $f0 now contains, e.g., 123.0
    
    # 3. Load 10.0 into another FPU register
    l.s $f1, ten_float
    
    # 4. Divide by 10.0 to get the correct float value
    div.s $f0, $f0, $f1     # $f0 now contains, e.g., 12.3
    
    # 5. Store this new float value in float_array at the current index
    la $t8, float_array     # Get base address of the float array
    add $t8, $t8, $t7       # Add offset (already calculated in $t7)
    s.s $f0, 0($t8)         # Store single-precision float
    # ==========================================================
    
    # Reset flags for next number (unchanged)
    addi $t1, $t1, 1
    li $t2, 0
    li $t3, 0
    li $t5, 0
    li $t6, 0
    li $t9, 0

skip_store:
    addi $t0, $t0, 1
    j parse_loop

store_last_number:
    beq $t5, 0, print_floats # Changed jump target
    # If there's a pending number at EOF, store it
    # The jump to store_number will handle both int and float storage
    jal store_number         # Use jal to return here, then jump to print
    # After returning, fall through to print_floats
    
# --- REPLACEMENT: PRINT FLOATS FROM THE NEW ARRAY ---
print_floats:
    li $t3, 0           # $t3 is our loop counter, i = 0

print_loop:
    bge $t3, $t1, exit  # if (i >= number_of_elements), exit

    # Calculate address: float_array[i]
    sll $t7, $t3, 2     # offset = i * 4
    la $t8, float_array # base address
    add $t8, $t8, $t7   # final address

    # Load the float from memory into the FPU
    lwc1 $f12, 0($t8)   # Use $f12 as it's the argument register for float syscalls

    # Print the float
    li $v0, 2           # syscall code for print_float
    syscall

    # Print a newline
    li $v0, 4           # syscall code for print_string
    la $a0, newline
    syscall

    addi $t3, $t3, 1    # i++
    j print_loop

exit:
    li $v0, 10
    syscall
