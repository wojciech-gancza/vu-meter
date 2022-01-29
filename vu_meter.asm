;-------------------------------------------------------------------------------

.include			"m32adef.inc"			; ATMega32

;-------------------------------------------------------------------------------
					.dseg	
					.equ 	os_stack_size 	= 128 	; size of machine stack

os_system_stack:	.byte	os_stack_size

;- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
					.cseg
					.org 	0

				; interupt vector 
ivect:				jmp 	initOS				; RESET
					jmp		empty				; INT0
					jmp		empty				; INT1
					jmp		empty				; INT2
					jmp		empty				; TIMER2 COMP
					jmp		timerTick1ms		; TIMER2 OVF
					jmp		empty				; TIMER1 CAPT
					jmp		empty				; TIMER1 COMPA
					jmp		empty				; TIMER1 COMPB
					jmp		empty				; TIMER1 OVF
					jmp		empty				; TIMER0 COMP
					jmp		empty				; TIMER0 OVF
					jmp		empty				; SPI, STC 
					jmp		empty				; USART, RXC
					jmp		empty				; USART, UDRE 
					jmp		empty				; USART, TXC
					jmp		empty				; ADC 
					jmp		empty				; EE_RDY
					jmp		empty				; ANA_COMP
					jmp		empty				; TWI
					jmp		empty			    ; SPM_RDY

empty:				reti

;-------------------------------------------------------------------------------

				; main excution flow
initOS:				cli
				; setting stack pointer to the end of the stack
					ldi		zh, high(os_system_stack+os_stack_size-1)
					ldi		zl, low(os_system_stack+os_stack_size-1)
					out		SPH, zh
					out		SPL, zl
					
					
				; set ports direction
				; output: (inactive: high)
				; 20 lines: PD0-7, PC0-7, PA4-7 - lines
				; 2 rows:	PB6-7
					ldi		r16, 0b11111111
					out		PORTC, r16
					out		PORTD, r16
					out		DDRC, r16
					out		DDRD, r16
					ldi		r16, 0b11110000
					out		PORTA, r16
					out		DDRA, r16
					ldi		r16, 0b11000000
					out		PORTB, r16
					out		DDRB, r16

				; set TIMER2 as main clock source 1ms at 8MHz:
				; FOC2 = 0   - default
				; WGM2 = 00  - normal
				; COM2 = 00  - OC2 disconnected
				; CS2  = 100 - /64
					ldi		r16, 0b00000100
					out		TCCR2, r16
				; count 125 tick until interupt
					ldi		r16, -125
					out		TCNT2, r16
				; enable timer2 overflow interupt
				; OCIE2 = 0
				; TOIE2 = 1
					ldi		r16, 0b01000000
					out 	TIMSK, r16

				; initialize display 
					ldi		r16, 0
					mov		r0, r16	; left bar value on bits 0:4
					mov		r1, r16 ; left dot value on bits 0:4
					mov		r2, r16 ; right bar value on bits 0:4
					mov		r3, r16 ; right dot value on bits 0:4
					mov		r4, r16	; display step counter
					rcall   displayOff
					rcall	clearBar

				; for tests only
					eor		r13, r13
				; /for tests only

				; main loop - reads interface and reacts on changes
				; all the important functionality is in inerupts
					sei
mainLoop:		 	rjmp	mainLoop		

;-------------------------------------------------------------------------------

.equ				DOT_DELAY = 200
.equ				DOT_DECAY = 4

setLeft:		; r16 - value
					cp		r16, r0
					brlt	notSet
					mov		r0, r16
					cp		r16, r1
					brlt	notSet
					mov     r1, r16
					ldi		r16, DOT_DELAY
					mov		r5, r16
notSet:				ret

setRight:		; r16 - value
					cp		r16, r2
					brlt	notSet
					mov		r2, r16
					cp		r16, r3
					brlt	notSet
					mov     r3, r16
					ldi		r16, DOT_DELAY
					mov		r6, r16
					ret

;-------------------------------------------------------------------------------

timerTick1ms:		push	r16
					in		r16, SREG
					push	r16

				; set counter back to -125
					ldi		r16, -125
					out		TCNT2, r16


				; update state of the display
					push	r17
					push	zl
					push	zh

					rcall	clearBar

handleDisplay:	; R4: 	bit0: 0:Left,    1:Right
				;	 	bit1: 0:Dot+Bar, 1:Bar
					inc		r4
					sbrc	r4, 0
					rjmp	timerStep_1

					rcall	selectL

					sbrc	r4, 1
					rjmp	timerStep10

timerStep00:		mov		r16, r0
					eor		r0, r0
					rcall	showBar

timerStep10:		mov		r16, r1
					rcall	addDot

					rjmp	handleDisplayEnd

timerStep_1:		rcall	selectR
					
					sbrc	r4, 1
					rjmp	timerStep11

timerStep01:		mov		r16, r2
					eor		r2, r2
					rcall	showBar

timerStep11:		mov		r16, r3
					rcall	addDot

handleDisplayEnd:	nop

handleDotDecay:		ldi		r16, $03 ; mask for tic counter - to perform dot decay
					and		r16, r4	
					brne	handleDotDecayEnd

handleFirstDot:		and 	r1, r1
					breq	handleSecondDot

					dec		r5
					brne	handleSecondDot
					dec		r1
					ldi		r16, DOT_DECAY
					mov		r5, r16

handleSecondDot:	and 	r3, r3
					breq	handleDotDecayEnd

					dec		r6
					brne	handleDotDecayEnd
					dec		r3
					ldi		r16, DOT_DECAY
					mov		r6, r16

handleDotDecayEnd:	nop

timerEnd:		; additional tick handling

						
				; for tests only
					mov		r16, r10
					rcall	setLeft
					mov		r16, r11
					rcall 	setRight
					dec		r12
					dec		r12
					brne	endOfInterupt
				; called aprox 4 times a second
					inc		r13
					inc		r13
					ldi		zl, low(2*testValues)
					ldi		zh, high(2*testValues)
					ldi		r16, 0
					add		zl, r13
					adc		zh, r16
					lpm		r16, z+
					mov		r10, r16
					lpm		r16, z
					mov		r11, r16
				; /for tests only

endOfInterupt:		pop		zh
					pop		zl
					pop		r17

					pop		r16
					out		SREG, r16
					pop		r16
					reti

testValues:			.db 	 7,  0,  8,  1,  9,  2, 10,  3, 11,  4, 14,  9,  4, 19, 1,  1
					.db 	 0,  0,  2,  2,  4,  4,  3,  3,  2,  4,  3,  3,  4,  2, 1,  1
					.db 	 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0,  0
					.db 	20,  0,  0,  0,  0, 18,  0,  0,  0,  0,  0,  0,  0,  0, 0,  0
					.db 	 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0,  0
					.db 	 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0,  0
					.db 	 0,  0,  0, 17,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0,  0
					.db 	 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0,  0
					.db 	 7,  0,  8,  1,  9,  2, 10,  3, 11,  4, 14,  9,  4, 19, 1,  1
					.db 	 0,  0,  2,  2,  4,  4,  3,  3,  2,  4,  3,  3,  4,  2, 1,  1
					.db 	 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0,  0
					.db 	20,  0,  0,  0,  0, 18,  0,  0,  0,  0,  0,  0,  0,  0, 0,  0
					.db 	 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0,  0
					.db 	 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0,  0
					.db 	 0,  0,  0, 17,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0,  0
					.db 	 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 0,  0
					

;-------------------------------------------------------------------------------

; display procedures setting state of led diodes in VU led bars.

selectL:		; modify R16
					in		r16, PORTB
					ori		r16, 0b11000000
					andi	r16, 0b10111111
					out		PORTB, r16
					ret

selectR:		; modify R16
					in		r16, PORTB
					ori		r16, 0b11000000
					andi	r16, 0b01111111
					out		PORTB, r16
					ret

displayOff:		; modify R16
					in		r16, PORTB
					ori		r16, 0b11000000
					out		PORTB, r16
					ret

clearBar:		; modify R16
					ldi		r16, 0b11111111
					out		PORTD, r16
					out		PORTC, r16
					in		r16, PORTA
					andi	r16, 0b00001111
					ori		r16, 0b11110000
					out		PORTA, r16
					ret


showBar:		; R16 - number of dots
				; modify ZL, ZH

					mov		zl, r16
					add		r16, r16
					add		r16, zl
					ldi		zl, low(2*barValues)
					ldi		zh, high(2*barValues)
					add		zl, r16
					ldi 	r16, 0
					adc		zh, r16

					lpm		r16, z+
					out		PORTD, r16

					lpm		r16, z+
					out		PORTC, r16

					lpm		r16, z
					in		zl, PORTA
					andi	zl, $0f
					or		r16, zl
					out		PORTA, r16
					ret

addDot:			; R16 - dot position
				; modify R17, ZL, ZH

					mov		zl, r16
					add		r16, r16
					add		r16, zl
					ldi		zl, low(2*dotValues)
					ldi		zh, high(2*dotValues)
					add		zl, r16
					ldi 	r16, 0
					adc		zh, r16

					in		r17, PORTD
					lpm		r16, z+
					and		r16, r17
					out		PORTD, r16

					in		r17, PORTC
					lpm		r16, z+
					and 	r16, r17
					out		PORTC, r16

					in		r17, PORTA
					lpm		r16, z
					and		r16, r17
					out		PORTA, r16
					ret

barValues:			.db		0b11111111, 0b11111111, 0b11110000,	\
					 		0b11111111, 0b11111111, 0b11100000,	\
							0b11111111, 0b11111111, 0b11000000,	\
							0b11111111, 0b11111111, 0b10000000,	\
							0b11111111, 0b11111111, 0b00000000,	\
							0b11111111, 0b01111111, 0b00000000, \
							0b11111111, 0b00111111, 0b00000000, \
							0b11111111, 0b00011111, 0b00000000, \
							0b11111111, 0b00001111, 0b00000000, \
							0b11111111, 0b00000111, 0b00000000, \
							0b11111111, 0b00000011, 0b00000000, \
							0b11111111, 0b00000001, 0b00000000, \
							0b11111111, 0b00000000, 0b00000000, \
							0b01111111, 0b00000000, 0b00000000, \
							0b00111111, 0b00000000, 0b00000000, \
							0b00011111, 0b00000000, 0b00000000, \
							0b00001111, 0b00000000, 0b00000000, \
							0b00000111, 0b00000000, 0b00000000, \
							0b00000011, 0b00000000, 0b00000000, \
							0b00000001, 0b00000000, 0b00000000, \
							0b00000000, 0b00000000, 0b00000000, \
							$00 ; align to full bytes count

dotValues:			.db		0b11111111, 0b11111111, 0b11110000,	\
					 		0b11111111, 0b11111111, 0b11100000,	\
							0b11111111, 0b11111111, 0b11010000,	\
							0b11111111, 0b11111111, 0b10110000,	\
							0b11111111, 0b11111111, 0b01110000,	\
							0b11111111, 0b01111111, 0b11110000, \
							0b11111111, 0b10111111, 0b11110000, \
							0b11111111, 0b11011111, 0b11110000, \
							0b11111111, 0b11101111, 0b11110000, \
							0b11111111, 0b11110111, 0b11110000, \
							0b11111111, 0b11111011, 0b11110000, \
							0b11111111, 0b11111101, 0b11110000, \
							0b11111111, 0b11111110, 0b11110000, \
							0b01111111, 0b11111111, 0b11110000, \
							0b10111111, 0b11111111, 0b11110000, \
							0b11011111, 0b11111111, 0b11110000, \
							0b11101111, 0b11111111, 0b11110000, \
							0b11110111, 0b11111111, 0b11110000, \
							0b11111011, 0b11111111, 0b11110000, \
							0b11111101, 0b11111111, 0b11110000, \
							0b11111110, 0b11111111, 0b11110000, \
							$00 ; align to full bytes count

;-------------------------------------------------------------------------------
