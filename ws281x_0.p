// \file
 //* WS281x LED strip driver for the BeagleBone Black.
 //*
 //* Drives up to 32 strips using the PRU hardware.  The ARM writes
 //* rendered frames into shared DDR memory and sets a flag to indicate
 //* how many pixels wide the image is.  The PRU then bit bangs the signal
 //* out the 32 GPIO pins and sets a done flag.
 //*
 //* To stop, the ARM can write a 0xFF to the command, which will
 //* cause the PRU code to exit.
 //*
 //* At 800 KHz:
 //*  0 is 0.25 usec high, 1 usec low
 //*  1 is 0.60 usec high, 0.65 usec low
 //*  Reset is 50 usec
 //
 // Pins are not contiguous.
 // 16 pins on GPIO0: 2 3 4 5 7 12 13 14 15 20 22 23 26 27 30 31
 // 10 pins on GPIO1: 12 13 14 15 16 17 18 19 28 29
 //  5 pins on GPIO2: 1 2 3 4 5
 //  8 pins on GPIO3: 14 15 16 17 18 19 20 21
 //
 // each pixel is stored in 4 bytes in the order GRBA (4th byte is ignored)
 //
 // while len > 0:
	 // for bit# = 24 down to 0:
		 // delay 600 ns
		 // read 16 registers of data, build zero map for gpio0
		 // read 10 registers of data, build zero map for gpio1
		 // read  5 registers of data, build zero map for gpio3
		 //
		 // Send start pulse on all pins on gpio0, gpio1 and gpio3
		 // delay 250 ns
		 // bring zero pins low
		 // delay 300 ns
		 // bring all pins low
	 // increment address by 32

 //*
 //* So to clock this out:
 //*  ____
 //* |  | |______|
 //* 0  250 600  1250 offset
 //*    250 350   650 delta
 //* 
 //*/


.origin 0
.entrypoint START

#include "ws281x.hp"

#define NOP       mov r0, r0

//===============================
// GPIO Pin Mapping

// Pins in GPIO0
#define gpio0_bit0 2
#define gpio0_bit1 3
//#define gpio0_bit2 4 // BROKEN
//#define gpio0_bit3 5 // BROKEN
#define gpio0_bit2 7
#define gpio0_bit3 8
#define gpio0_bit4 9
#define gpio0_bit5 10
#define gpio0_bit6 11
#define gpio0_bit7 14
#define gpio0_bit8 20
#define gpio0_bit9 22
#define gpio0_bit10 23
#define gpio0_bit11 26
#define gpio0_bit12 27
#define gpio0_bit13 30
#define gpio0_bit14 31

// Pins in GPIO1
#define gpio1_bit0 12
#define gpio1_bit1 13
#define gpio1_bit2 14
#define gpio1_bit3 15
#define gpio1_bit4 16
#define gpio1_bit5 17
#define gpio1_bit6 18
#define gpio1_bit7 19
#define gpio1_bit8 28
#define gpio1_bit9 29

#define GPIO0_LED_MASK (0\
|(1<<gpio0_bit0)\
|(1<<gpio0_bit1)\
|(1<<gpio0_bit2)\
|(1<<gpio0_bit3)\
|(1<<gpio0_bit4)\
|(1<<gpio0_bit5)\
|(1<<gpio0_bit6)\
|(1<<gpio0_bit7)\
|(1<<gpio0_bit8)\
|(1<<gpio0_bit9)\
|(1<<gpio0_bit10)\
|(1<<gpio0_bit11)\
|(1<<gpio0_bit12)\
|(1<<gpio0_bit13)\
|(1<<gpio0_bit14)\
)

#define GPIO1_LED_MASK (0\
|(1<<gpio1_bit0)\
|(1<<gpio1_bit1)\
|(1<<gpio1_bit2)\
|(1<<gpio1_bit3)\
|(1<<gpio1_bit4)\
|(1<<gpio1_bit5)\
|(1<<gpio1_bit6)\
|(1<<gpio1_bit7)\
|(1<<gpio1_bit8)\
)
//|(1<<gpio1_bit9)\




/** Register map */
#define data_addr r0
#define data_len r1
#define gpio0_zeros r2
#define gpio1_zeros r3
#define gpio2_zeros r4
#define gpio3_zeros r5
#define bit_num r6
#define sleep_counter r7
#define addr_reg r8
#define temp_reg r9
#define temp2_reg r27
// r10 - r26 are used for temp storage and bitmap processing


/** Sleep a given number of nanoseconds with 10 ns resolution.
 *
 * This busy waits for a given number of cycles.  Not for use
 * with things that must happen on a tight schedule.
 */
.macro SLEEPNS
.mparam ns,inst,lab
#ifdef CONFIG_WS2812
    MOV sleep_counter, (ns/5)-1-inst // ws2812 -- low speed
#else
    MOV sleep_counter, (ns/10)-1-inst // ws2811 -- high speed
#endif
lab:
    SUB sleep_counter, sleep_counter, 1
    QBNE lab, sleep_counter, 0
.endm


/** Wait for the cycle counter to reach a given value */
.macro WAITNS
.mparam ns,lab
    MOV r8, 0x22000 // control register
lab:
	LBBO r9, r8, 0xC, 4 // read the cycle counter
//	SUB r9, r9, sleep_counter 
#ifdef CONFIG_WS2812
	QBGT lab, r9, 2*(ns)/5
#else
	QBGT lab, r9, (ns)/5
#endif
.endm

/** Reset the cycle counter */
.macro RESET_COUNTER
		// Disable the counter and clear it, then re-enable it
		MOV addr_reg, 0x22000 // control register
		LBBO r9, addr_reg, 0, 4
		CLR r9, r9, 3 // disable counter bit
		SBBO r9, addr_reg, 0, 4 // write it back

		MOV temp2_reg, 0
		SBBO temp2_reg, addr_reg, 0xC, 4 // clear the timer

		SET r9, r9, 3 // enable counter bit
		SBBO r9, addr_reg, 0, 4 // write it back

		// Read the current counter value
		// Should be zero.
		LBBO sleep_counter, addr_reg, 0xC, 4
.endm

START:
    // Enable OCP master port
    // clear the STANDBY_INIT bit in the SYSCFG register,
    // otherwise the PRU will not be able to write outside the
    // PRU memory space and to the BeagleBon's pins.
    LBCO	r0, C4, 4, 4
    CLR		r0, r0, 4
    SBCO	r0, C4, 4, 4

    // Configure the programmable pointer register for PRU0 by setting
    // c28_pointer[15:0] field to 0x0120.  This will make C28 point to
    // 0x00012000 (PRU shared RAM).
    MOV		r0, 0x00000120
    MOV		r1, CTPPR_0
    ST32	r0, r1

    // Configure the programmable pointer register for PRU0 by setting
    // c31_pointer[15:0] field to 0x0010.  This will make C31 point to
    // 0x80001000 (DDR memory).
    MOV		r0, 0x00100000
    MOV		r1, CTPPR_1
    ST32	r0, r1

    // Write a 0x1 into the response field so that they know we have started
    MOV r2, #0x1
    SBCO r2, CONST_PRUDRAM, 12, 4


	MOV r20, 0xFFFFFFFF

	/*
// Enable to generate a reference signal of 010101... to GPIO0
_REFERENCE_SIGNAL_LOOP:
	// Send 0
	MOV r10, GPIO0 | GPIO_SETDATAOUT
	SBBO r20, r10, 0, 4
	SLEEPNS 250, 3, after_set0_wait_loop

	NOP

	MOV r10, GPIO0 | GPIO_CLEARDATAOUT
	SBBO r20, r10, 0, 4
	SLEEPNS 1000, 3, after_clear0_wait_loop

	NOP

	// Send 1
	MOV r10, GPIO0 | GPIO_SETDATAOUT
	SBBO r20, r10, 0, 4
	SLEEPNS 1000, 3, after_set1_wait_loop

	NOP

	MOV r10, GPIO0 | GPIO_CLEARDATAOUT
	SBBO r20, r10, 0, 4
	SLEEPNS 250, 3, after_clear1_wait_loop

	QBA _REFERENCE_SIGNAL_LOOP */

    // Wait for the start condition from the main program to indicate
    // that we have a rendered frame ready to clock out.  This also
    // handles the exit case if an invalid value is written to the start
    // start position.
_LOOP:
    // Load the pointer to the buffer from PRU DRAM into r0 and the
    // length (in bytes-bit words) into r1.
    // start command into r2
    LBCO      data_addr, CONST_PRUDRAM, 0, 12

    // Wait for a non-zero command
    QBEQ _LOOP, r2, #0

    // Reset the sleep timer
    RESET_COUNTER

    // Zero out the start command so that they know we have received it
    // This allows maximum speed frame drawing since they know that they
    // can now swap the frame buffer pointer and write a new start command.
    MOV r3, 0
    SBCO r3, CONST_PRUDRAM, 8, 4

    // Command of 0xFF is the signal to exit
    QBEQ EXIT, r2, #0xFF

WORD_LOOP:
	// for bit in 24 to 0
	MOV bit_num, 24

	BIT_LOOP:
		SUB bit_num, bit_num, 1
		/** Macro to generate the mask of which bits are zero.
		 * For each of these registers, set the
		 * corresponding bit in the gpio0_zeros register if
		 * the current bit is set in the strided register.
		 */
		#define TEST_BIT(regN,gpioN,bitN) \
			QBBS gpioN##_##regN##_skip, regN, bit_num; \
			SET gpioN##_zeros, gpioN##_zeros, gpioN##_##bitN ; \
			gpioN##_##regN##_skip: ; \

		// Load 16 registers of data, starting at r10
		LBBO r10, r0, 0, 16*4
		MOV gpio0_zeros, 0

		TEST_BIT(r10, gpio0, bit0)
		TEST_BIT(r11, gpio0, bit1)
		TEST_BIT(r12, gpio0, bit2)
		TEST_BIT(r13, gpio0, bit3)
		TEST_BIT(r14, gpio0, bit4)
		TEST_BIT(r15, gpio0, bit5)
		TEST_BIT(r16, gpio0, bit6)
		TEST_BIT(r17, gpio0, bit7)
		TEST_BIT(r18, gpio0, bit8)
		TEST_BIT(r19, gpio0, bit9)
		TEST_BIT(r20, gpio0, bit10)
		TEST_BIT(r21, gpio0, bit11)
		TEST_BIT(r22, gpio0, bit12)
		TEST_BIT(r23, gpio0, bit13)
		TEST_BIT(r24, gpio0, bit14)

		MOV gpio1_zeros, 0
		TEST_BIT(r25, gpio1, bit0)

		// Load 8 more registers of data
		LBBO r10, r0, 16*4, 8*4
		// Data loaded


		// Load the address(es) of the GPIO devices
		MOV r20, GPIO0_LED_MASK
		MOV r21, GPIO1_LED_MASK

		// Clear lines from last bit
		MOV r22, GPIO0 | GPIO_CLEARDATAOUT
		MOV r23, GPIO1 | GPIO_CLEARDATAOUT

		WAITNS 900, wait_one_time
		SBBO r20, r22, 0, 4
		SBBO r21, r23, 0, 4

		MOV r22, GPIO0 | GPIO_SETDATAOUT
		MOV r23, GPIO1 | GPIO_SETDATAOUT

		// Wait until the end of the frame (including the time it takes to reset the counter)
		WAITNS 1150, wait_frame_spacing_time
		RESET_COUNTER

		// Send all the start bits
		SBBO r20, r22, 0, 4
		SBBO r21, r23, 0, 4

		// Reconfigure r10-13 for clearing the bits
		MOV r22, GPIO0 | GPIO_CLEARDATAOUT
		MOV r23, GPIO1 | GPIO_CLEARDATAOUT

		// Test some more bits to pass the time
		TEST_BIT(r10, gpio1, bit1)
		TEST_BIT(r11, gpio1, bit2)
		TEST_BIT(r12, gpio1, bit3)
		TEST_BIT(r13, gpio1, bit4)
		TEST_BIT(r14, gpio1, bit5)
		TEST_BIT(r15, gpio1, bit6)
		TEST_BIT(r16, gpio1, bit7)
		TEST_BIT(r17, gpio1, bit8)

		WAITNS 240, wait_zero_time

		// turn off all the zero bits
		SBBO gpio0_zeros, r22, 0, 4
		SBBO gpio1_zeros, r23, 0, 4

		// One bits get turned off in the next round of the loop
		QBNE BIT_LOOP, bit_num, 0

	// The RGB streams have been clocked out
	// Move to the next pixel on each row
	ADD data_addr, data_addr, 48 * 4
	SUB data_len, data_len, 1
	QBNE WORD_LOOP, data_len, #0

	// Final clear for the word
	MOV r20, GPIO0_LED_MASK
	MOV r21, GPIO1_LED_MASK
	MOV r10, GPIO0 | GPIO_CLEARDATAOUT
	MOV r11, GPIO1 | GPIO_CLEARDATAOUT

	WAITNS 1000, end_of_frame_clear_wait
	SBBO r20, r10, 0, 4
	SBBO r21, r11, 0, 4

    // Delay at least 50 usec; this is the required reset
    // time for the LED strip to update with the new pixels.
    SLEEPNS 50000, 1, reset_time

    // Write out that we are done!
    // Store a non-zero response in the buffer so that they know that we are done
    // aso a quick hack, we write the counter so that we know how
    // long it took to write out.
    MOV r8, 0x22000 // control register
    LBBO r2, r8, 0xC, 4
    SBCO r2, CONST_PRUDRAM, 12, 4

    // Go back to waiting for the next frame buffer
    QBA _LOOP

EXIT:
    // Write a 0xFF into the response field so that they know we're done
    MOV r2, #0xFF
    SBCO r2, CONST_PRUDRAM, 12, 4

#ifdef AM33XX
    // Send notification to Host for program completion
    MOV R31.b0, PRU0_ARM_INTERRUPT+16
#else
    MOV R31.b0, PRU0_ARM_INTERRUPT
#endif

    HALT
